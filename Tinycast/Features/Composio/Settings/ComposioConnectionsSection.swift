import SwiftUI

/// A Composio key, the apps tagged for chat, and servers saved earlier.
struct ComposioConnectionsSection: View {
    @Environment(ComposioCoordinator.self) private var composio
    @Environment(MCPCoordinator.self) private var mcp
    @Environment(AppSettings.self) private var appSettings
    @Environment(ComposioConnectionsStore.self) private var store
    @Environment(MCPSettingsStore.self) private var servers

    @State private var browserPresented = false
    @State private var apiKey = ""
    @State private var keyMessage: String?
    @State private var pendingRemoval: Removal?

    var body: some View {
        @Bindable var appSettings = appSettings
        Section {
            Toggle(isOn: $appSettings.mcpEnabled) {
                SettingsFeatureToggleLabel(
                    anchor: .aiConnections, title: "Enable connections",
                    subtitle: "Tagged apps and MCP servers are offered in chat.")
            }
            apiKeyRow
            Group {
                if store.connections.isEmpty && earlierServers.isEmpty {
                    Text("No connections yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(store.connections) { connection in
                    connectionRow(connection)
                }
                ForEach(earlierServers) { server in
                    earlierRow(server)
                }
                Button {
                    browserPresented = true
                } label: {
                    Label {
                        SettingsRowTitle(.aiConnections, "Add connection")
                    } icon: {
                        Image(systemName: "plus")
                            .foregroundStyle(.primary)
                    }
                }
            }
            .settingsEnabled(appSettings.mcpEnabled)
            if let message = keyMessage ?? composio.actionError {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
        } header: {
            SettingsSectionHeader(.aiConnections)
        } footer: {
            Text("Tag an app to reach it as @name. A chat asks before its first tool call.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .settingsEditorPanel(isPresented: $browserPresented) {
            ComposioConnectionsPanel(onDone: { browserPresented = false })
        }
        .confirmationDialog(
            removalTitle, isPresented: removalBinding, titleVisibility: .visible,
            presenting: pendingRemoval
        ) { removal in
            Button("Remove", role: .destructive) { remove(removal) }
        } message: { _ in
            Text("Its tools stop being offered, and its stored credentials are deleted.")
        }
    }

    private var apiKeyRow: some View {
        SettingsRow(title: "Composio API key", subtitle: keySubtitle, anchor: .aiConnections) {
            Image(systemName: "key")
                .foregroundStyle(.primary)
        } trailing: {
            SecureField(composio.hasAPIKey ? "Saved" : "Project key", text: $apiKey)
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)
            Button(composio.hasAPIKey && apiKey.isEmpty ? "Remove" : "Save") {
                saveOrRemoveKey()
            }
        }
    }

    private var keySubtitle: String? {
        composio.hasAPIKey ? "Saved in your login Keychain" : "From composio.dev, for this Mac"
    }

    private var earlierServers: [MCPServer] {
        let owned = Set(store.connections.map(\.id))
        return servers.servers.filter { !owned.contains($0.id) }
    }

    private func connectionRow(_ connection: ComposioConnection) -> some View {
        let status = mcp.status(of: connection.id)
        return SettingsRow(title: connection.title, subtitle: "@\(connection.tag) · \(status.label)") {
            ComposioMark(url: ComposioAPI.httpsURL(connection.logoURL), title: connection.title)
        } trailing: {
            Button {
                Task { await composio.connect(toolkitSlug: connection.toolkitSlug) }
            } label: {
                Image(systemName: "link")
            }
            .buttonStyle(.plain)
            .disabled(composio.busySlug == connection.toolkitSlug)
            .help("Connect \(connection.title)")
            .accessibilityLabel("Connect \(connection.title)")
            Button {
                pendingRemoval = .connection(connection)
            } label: {
                Image(systemName: "trash").foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .help("Remove \(connection.title)")
            .accessibilityLabel("Remove \(connection.title)")
        }
    }

    private func earlierRow(_ server: MCPServer) -> some View {
        SettingsRow(title: server.title, subtitle: "@\(server.slug) · \(server.transport.summary)") {
            Image(systemName: "wrench.and.screwdriver")
                .foregroundStyle(.primary)
        } trailing: {
            Button {
                pendingRemoval = .earlier(server)
            } label: {
                Image(systemName: "trash").foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .help("Remove \(server.title)")
            .accessibilityLabel("Remove \(server.title)")
        }
    }

    private var removalTitle: String {
        switch pendingRemoval {
        case .connection(let connection): return "Remove \(connection.title)?"
        case .earlier(let server): return "Remove \(server.title)?"
        case nil: return "Remove this connection?"
        }
    }

    private var removalBinding: Binding<Bool> {
        Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } })
    }

    private func saveOrRemoveKey() {
        if composio.hasAPIKey && apiKey.isEmpty {
            keyMessage = composio.removeAPIKey()
        } else {
            keyMessage = composio.saveAPIKey(apiKey)
            if keyMessage == nil { apiKey = "" }
        }
    }

    private func remove(_ removal: Removal) {
        pendingRemoval = nil
        switch removal {
        case .connection(let connection):
            Task { await composio.untag(connection) }
        case .earlier(let server):
            do {
                try mcp.remove(server.id)
                keyMessage = nil
            } catch {
                keyMessage =
                    "\(server.title) was kept: its credentials could not be removed from your login Keychain."
            }
        }
    }
}

private enum Removal: Identifiable {
    case connection(ComposioConnection)
    case earlier(MCPServer)

    var id: UUID {
        switch self {
        case .connection(let connection): return connection.id
        case .earlier(let server): return server.id
        }
    }
}
