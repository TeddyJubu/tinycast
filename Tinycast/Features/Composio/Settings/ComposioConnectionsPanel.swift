import SwiftUI

/// One click connects an app or a public MCP address and offers it in chat.
struct ComposioConnectionsPanel: View {
    @Environment(ComposioCoordinator.self) private var composio
    @Environment(ComposioConnectionsStore.self) private var store

    let onDone: () -> Void

    @State private var query = ""
    @State private var searchTask: Task<Void, Never>?
    @State private var apiKey = ""
    @State private var keyMessage: String?
    @State private var serverURL = ""
    @State private var serverAuth = ComposioMCPAuth.none
    @State private var pendingRemoval: ComposioToolkit?

    var body: some View {
        VStack(spacing: 0) {
            SettingsEditorHeader(
                title: "Connections",
                subtitle: "Click Connect. Chat can use it as @name."
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Spacing.dialogInset)
            .padding(.top, Theme.Spacing.dialogInset)
            .padding(.bottom, Theme.Spacing.xl)
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer
        }
        .frame(
            width: Theme.Size.composioConnectionsPanel.width,
            height: Theme.Size.composioConnectionsPanel.height)
        .settingsEditorPanelSurface(controlsOnGlass: false)
        .releasesFocusOnOutsideClick()
        .task {
            guard composio.hasAPIKey else { return }
            await composio.loadCatalog(search: "")
            await composio.refreshAccounts()
        }
        .onChange(of: composio.hasAPIKey) { _, hasKey in
            guard hasKey else { return }
            Task {
                await composio.loadCatalog(search: query)
                await composio.refreshAccounts()
            }
        }
        .onDisappear {
            searchTask?.cancel()
            composio.stopPolling()
        }
        .confirmationDialog(
            "Remove \(pendingRemoval?.name ?? "this connection")?",
            isPresented: removalBinding, titleVisibility: .visible, presenting: pendingRemoval
        ) { toolkit in
            Button("Remove", role: .destructive) {
                guard let connection = store.connection(toolkitSlug: toolkit.slug) else { return }
                Task { await composio.untag(connection) }
            }
        } message: { _ in
            Text("Chat stops offering it. You can connect it again from this list.")
        }
    }

    @ViewBuilder private var content: some View {
        if composio.hasAPIKey {
            catalog
        } else {
            keyPrompt
        }
    }

    private var keyPrompt: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Text("Paste a Composio project key once. It stays in your login Keychain.")
                .font(.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Theme.Spacing.md) {
                SecureField("Project key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                Button("Save") {
                    keyMessage = composio.saveAPIKey(apiKey)
                    if keyMessage == nil { apiKey = "" }
                }
                .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if let keyMessage {
                Text(keyMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.dialogInset)
    }

    private var catalog: some View {
        VStack(spacing: Theme.Spacing.lg) {
            mcpRow
            TextField("Search apps", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, Theme.Spacing.dialogInset)
                .onChange(of: query) { _, newValue in
                    searchTask?.cancel()
                    searchTask = Task {
                        try? await Task.sleep(for: .milliseconds(250))
                        guard !Task.isCancelled else { return }
                        await composio.loadCatalog(search: newValue)
                    }
                }
            if let catalogError = composio.catalogError {
                Text(catalogError)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Theme.Spacing.dialogInset)
            }
            ScrollView {
                if composio.isLoadingCatalog && composio.catalog.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 160)
                } else if composio.catalog.isEmpty {
                    Text("No apps match.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 160)
                } else {
                    LazyVGrid(columns: columns, spacing: Theme.Spacing.lg) {
                        ForEach(composio.catalog) { toolkit in
                            ComposioToolkitCard(
                                toolkit: toolkit,
                                connection: store.connection(toolkitSlug: toolkit.slug),
                                needsSignIn: needsSignIn(toolkit),
                                isBusy: composio.busySlug == toolkit.slug,
                                onUse: { Task { await composio.use(toolkit) } },
                                onSignIn: { Task { await composio.connect(toolkitSlug: toolkit.slug) } },
                                onRemove: { pendingRemoval = toolkit })
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.dialogInset)
                    .padding(.bottom, Theme.Spacing.xl)
                }
            }
        }
    }

    private var mcpRow: some View {
        HStack(spacing: Theme.Spacing.md) {
            TextField("https://mcp.example.com/mcp", text: $serverURL)
                .textFieldStyle(.roundedBorder)
            Picker("Sign-in", selection: $serverAuth) {
                ForEach(ComposioMCPAuth.allCases) { auth in
                    Text(auth.title).tag(auth)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
            .accessibilityLabel("Sign-in")
            Button("Connect") { connectServer() }
                .disabled(serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || composio.busySlug != nil)
        }
        .padding(.horizontal, Theme.Spacing.dialogInset)
        .padding(.top, Theme.Spacing.lg)
    }

    private var footer: some View {
        HStack {
            if let actionError = composio.actionError {
                Text(actionError)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            Button("Done", action: onDone)
                .buttonStyle(.modalAction(.primary, fillsWidth: false))
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, Theme.Spacing.xxl)
        .padding(.vertical, Theme.Spacing.xl)
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 156), spacing: Theme.Spacing.lg)]
    }

    private var removalBinding: Binding<Bool> {
        Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } })
    }

    private func needsSignIn(_ toolkit: ComposioToolkit) -> Bool {
        store.connection(toolkitSlug: toolkit.slug) != nil && !toolkit.noAuth
            && !composio.connectedSlugs.contains(toolkit.slug)
    }

    private func connectServer() {
        let url = serverURL
        let auth = serverAuth
        Task {
            await composio.addMCPServer(url: url, auth: auth)
            if composio.actionError == nil {
                serverURL = ""
                serverAuth = .none
            }
        }
    }
}

private struct ComposioToolkitCard: View {
    let toolkit: ComposioToolkit
    let connection: ComposioConnection?
    let needsSignIn: Bool
    let isBusy: Bool
    let onUse: () -> Void
    let onSignIn: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.md) {
                ComposioMark(url: ComposioAPI.httpsURL(toolkit.logoURL), title: toolkit.name)
                Text(toolkit.name)
                    .font(Theme.Typography.rowTitle)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if !toolkit.description.isEmpty {
                Text(toolkit.description)
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(2)
            }
            action
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
        .background(
            Theme.Colors.controlSurface,
            in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var action: some View {
        if connection == nil {
            Button("Connect", action: onUse)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isBusy)
                .accessibilityLabel("Connect \(toolkit.name)")
        } else if needsSignIn {
            Button("Sign in", action: onSignIn)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isBusy)
                .accessibilityLabel("Sign in to \(toolkit.name)")
        } else {
            HStack(spacing: Theme.Spacing.sm) {
                Text("@\(connection?.tag ?? "")")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Button(action: onRemove) {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .disabled(isBusy)
                .accessibilityLabel("Remove \(toolkit.name)")
            }
        }
    }
}
