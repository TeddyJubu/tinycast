import AppKit
import Foundation
import Observation

/// Connects and tags Composio apps, and projects each tag into the MCP server chat already runs.
@MainActor
@Observable
final class ComposioCoordinator {
    private let settings: AppSettings
    private let store: ComposioConnectionsStore
    private let servers: MCPSettingsStore
    private let mcp: MCPCoordinator

    private(set) var catalog: [ComposioToolkit] = []
    private(set) var isLoadingCatalog = false
    private(set) var catalogError: String?
    private(set) var actionError: String?
    private(set) var connectedSlugs: Set<String> = []
    private(set) var busySlug: String?
    private(set) var hasAPIKey: Bool

    @ObservationIgnored private var liveClient: ComposioClient?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var refreshedAt: Date?
    private static let refreshInterval: TimeInterval = 10 * 60

    init(
        settings: AppSettings, store: ComposioConnectionsStore, servers: MCPSettingsStore,
        mcp: MCPCoordinator
    ) {
        self.settings = settings
        self.store = store
        self.servers = servers
        self.mcp = mcp
        hasAPIKey = (try? ComposioSecretStore.hasAPIKey()) ?? false
    }

    func saveAPIKey(_ key: String) -> String? {
        do {
            try ComposioSecretStore.setAPIKey(key)
            hasAPIKey = (try? ComposioSecretStore.hasAPIKey()) ?? false
            liveClient = nil
            refreshedAt = nil
            actionError = nil
            if hasAPIKey { refreshSessions() }
            return nil
        } catch {
            return "The API key could not be saved to your login Keychain."
        }
    }

    func removeAPIKey() -> String? {
        do {
            try ComposioSecretStore.removeAPIKey()
            hasAPIKey = false
            liveClient = nil
            refreshedAt = nil
            for connection in store.connections {
                try? MCPSecretStore().remove(for: connection.id)
            }
            mcp.applyEnabled()
            return nil
        } catch {
            return "The API key could not be removed from your login Keychain."
        }
    }

    func loadCatalog(search: String) async {
        isLoadingCatalog = true
        defer { isLoadingCatalog = false }
        do {
            catalog = try await tryClient().toolkits(search: search)
            catalogError = nil
        } catch {
            catalogError = error.localizedDescription
        }
    }

    func refreshAccounts() async {
        guard let client = try? tryClient() else { return }
        connectedSlugs = (try? await client.activeSlugs(userID: store.userID)) ?? connectedSlugs
    }

    func connect(toolkitSlug: String) async {
        await run(slug: toolkitSlug) { client in
            let sessionID: String
            if let existing = self.store.connection(toolkitSlug: toolkitSlug) {
                sessionID = existing.sessionID
            } else {
                let endpoint = try await client.createSession(
                    userID: self.store.userID, toolkitSlug: toolkitSlug)
                guard endpoint.acceptsCredential else {
                    throw ComposioAPI.Failure(message: "Composio returned an unexpected address.")
                }
                sessionID = endpoint.sessionID
            }
            let link = try await client.connectLink(sessionID: sessionID, toolkitSlug: toolkitSlug)
            guard NSWorkspace.shared.open(link) else {
                throw ComposioAPI.Failure(message: "The sign-in page could not be opened.")
            }
            self.poll(toolkitSlug)
        }
    }

    func tag(_ toolkit: ComposioToolkit) async {
        guard store.connection(toolkitSlug: toolkit.slug) == nil else { return }
        await run(slug: toolkit.slug) { client in
            try await self.tagSession(
                client: client, toolkitSlug: toolkit.slug, name: toolkit.name, logoURL: toolkit.logoURL,
                kind: .app)
        }
    }

    func untag(_ connection: ComposioConnection) async {
        let slug = connection.toolkitSlug
        do {
            try mcp.remove(connection.id)
            store.remove(id: connection.id)
            actionError = nil
        } catch {
            actionError =
                "\(connection.title) was kept: its credentials could not be removed from your login Keychain."
            return
        }
        guard connection.kind == .mcpServer, let client = try? tryClient() else { return }
        do {
            try await client.deleteMCPServer(slug: slug)
        } catch {
            actionError = error.localizedDescription
        }
    }

    func addMCPServer(name: String, url: String, auth: ComposioMCPAuth) async {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            actionError = "Name the server."
            return
        }
        let mcpURL: URL
        do {
            mcpURL = try ComposioAPI.validateMCPURL(url)
        } catch {
            actionError = error.localizedDescription
            return
        }
        let requested = ComposioAPI.customSlug(from: trimmedName)
        await run(slug: requested) { client in
            let registered = try await client.registerMCPServer(
                slug: requested, name: trimmedName, appURL: mcpURL.absoluteString, auth: auth,
                discoveryURL: auth == .oauth ? ComposioAPI.oauthDiscoveryURL(for: mcpURL) : nil)
            guard self.store.connection(toolkitSlug: registered) == nil else {
                throw ComposioAPI.Failure(message: "\(trimmedName) is already tagged.")
            }
            if auth == .none { try await client.syncMCPServer(slug: registered) }
            try await self.tagSession(
                client: client, toolkitSlug: registered, name: trimmedName, logoURL: nil, kind: .mcpServer)
            if auth != .none {
                let sessionID = self.store.connection(toolkitSlug: registered)?.sessionID ?? ""
                let link = try await client.connectLink(sessionID: sessionID, toolkitSlug: registered)
                guard NSWorkspace.shared.open(link) else {
                    throw ComposioAPI.Failure(message: "The sign-in page could not be opened.")
                }
                self.poll(registered)
            }
        }
    }

    /// Reused for ten minutes, so opening chat does not mint a session.
    func refreshSessions() {
        if let refreshedAt, Date().timeIntervalSince(refreshedAt) < Self.refreshInterval { return }
        guard settings.aiEnabled, settings.mcpEnabled, !store.connections.isEmpty else { return }
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            await self?.refreshSessionsNow()
        }
    }

    func stopPolling() { pollTask?.cancel() }

    private func refreshSessionsNow() async {
        guard let client = try? tryClient() else { return }
        let snapshot = store.connections
        for connection in snapshot {
            if Task.isCancelled { return }
            guard store.connection(id: connection.id) != nil else { continue }
            do {
                let endpoint = try await client.createSession(
                    userID: store.userID, toolkitSlug: connection.toolkitSlug)
                // A rejected address leaves the URL already saved for this tag.
                guard endpoint.acceptsCredential else { continue }
                guard endpoint.mcpURL != connection.sessionMCPURL || endpoint.sessionID != connection.sessionID
                else { continue }
                var updated = connection
                updated.sessionID = endpoint.sessionID
                updated.sessionMCPURL = endpoint.mcpURL
                try project(updated, apiKey: client.apiKey)
            } catch {
                // Offline, or one toolkit: the URL already saved for it keeps working.
                continue
            }
        }
        refreshedAt = Date()
    }

    private func tagSession(
        client: ComposioClient, toolkitSlug: String, name: String, logoURL: String?,
        kind: ComposioConnection.Kind
    ) async throws {
        let endpoint = try await client.createSession(userID: store.userID, toolkitSlug: toolkitSlug)
        guard endpoint.acceptsCredential else {
            throw ComposioAPI.Failure(message: "Composio returned an unexpected address.")
        }
        let connection = ComposioConnection(
            id: UUID(), toolkitSlug: toolkitSlug, name: name, tag: MCPSlug.normalize(name),
            logoURL: logoURL, sessionID: endpoint.sessionID, sessionMCPURL: endpoint.mcpURL, kind: kind)
        try project(connection, apiKey: client.apiKey)
        refreshedAt = Date()
    }

    private func project(_ connection: ComposioConnection, apiKey: String) throws {
        let preserving = servers.server(id: connection.id)
        guard let server = ComposioServerProjection.server(from: connection, preserving: preserving) else {
            throw ComposioAPI.Failure(message: "Composio returned an unexpected address.")
        }
        try mcp.save(server, secrets: MCPSecretStore.Secrets(headerValue: apiKey))
        var stored = connection
        if let saved = servers.server(id: connection.id) { stored.tag = saved.slug }
        store.upsert(stored)
    }

    private func poll(_ slug: String) {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            for _ in 0..<100 {
                try? await Task.sleep(for: .seconds(3))
                if Task.isCancelled { return }
                await self?.refreshAccounts()
                if self?.connectedSlugs.contains(slug) == true {
                    self?.actionError = nil
                    return
                }
            }
        }
    }

    private func run(slug: String, _ work: (ComposioClient) async throws -> Void) async {
        busySlug = slug
        defer { busySlug = nil }
        do {
            try await work(tryClient())
            actionError = nil
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func tryClient() throws -> ComposioClient {
        guard let key = try ComposioSecretStore.apiKey() else {
            throw ComposioAPI.Failure(message: "Add a Composio API key first.")
        }
        if let liveClient, liveClient.apiKey == key { return liveClient }
        let created = ComposioClient(apiKey: key)
        liveClient = created
        return created
    }
}
