import SwiftUI

/// Connect an app, tag it for chat, or register a remote MCP server.
struct ComposioConnectionsPanel: View {
    @Environment(ComposioCoordinator.self) private var composio
    @Environment(ComposioConnectionsStore.self) private var store

    let onDone: () -> Void

    @State private var query = ""
    @State private var page = Page.apps
    @State private var searchTask: Task<Void, Never>?
    @State private var serverName = ""
    @State private var serverURL = ""
    @State private var serverAuth = ComposioMCPAuth.none
    @State private var pendingUntag: ComposioToolkit?

    var body: some View {
        VStack(spacing: 0) {
            SettingsEditorHeader(
                title: "Connections",
                subtitle: "Connect an app or add a remote MCP server, then tag the ones chat may use."
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Spacing.dialogInset)
            .padding(.top, Theme.Spacing.dialogInset)
            .padding(.bottom, Theme.Spacing.xl)
            Divider()
            pagePicker
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
            await composio.loadCatalog(search: "")
            await composio.refreshAccounts()
        }
        .onDisappear {
            searchTask?.cancel()
            composio.stopPolling()
        }
        .confirmationDialog(
            "Remove the \(pendingUntag?.name ?? "app") tag?",
            isPresented: untagBinding, titleVisibility: .visible, presenting: pendingUntag
        ) { toolkit in
            Button("Remove tag", role: .destructive) {
                guard let connection = store.connection(toolkitSlug: toolkit.slug) else { return }
                Task { await composio.untag(connection) }
            }
        } message: { _ in
            Text("Chat stops offering it. You can tag it again from this list.")
        }
    }

    private var pagePicker: some View {
        Picker("Show", selection: $page) {
            ForEach(Page.allCases) { page in
                Text(page.title).tag(page)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, Theme.Spacing.dialogInset)
        .padding(.vertical, Theme.Spacing.lg)
        .accessibilityLabel("Connections")
    }

    @ViewBuilder private var content: some View {
        switch page {
        case .apps: apps
        case .mcpServer: mcpServer
        }
    }

    private var apps: some View {
        VStack(spacing: Theme.Spacing.lg) {
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
                                isConnected: toolkit.noAuth || composio.connectedSlugs.contains(toolkit.slug),
                                isBusy: composio.busySlug == toolkit.slug,
                                onConnect: { Task { await composio.connect(toolkitSlug: toolkit.slug) } },
                                onTag: { Task { await composio.tag(toolkit) } },
                                onUntag: { pendingUntag = toolkit })
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.dialogInset)
                    .padding(.bottom, Theme.Spacing.xl)
                }
            }
        }
    }

    private var mcpServer: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            Text("Composio registers this server and you tag it like an app. It has to be a public HTTPS address.")
                .font(.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            SettingsEditorField("Name") {
                TextField("Acme", text: $serverName)
                    .settingsEditorTextField()
            }
            SettingsEditorField("URL") {
                TextField("https://mcp.example.com/mcp", text: $serverURL)
                    .settingsEditorTextField()
            }
            SettingsEditorField("Sign-in") {
                Picker("Sign-in", selection: $serverAuth) {
                    ForEach(ComposioMCPAuth.allCases) { auth in
                        Text(auth.title).tag(auth)
                    }
                }
                .labelsHidden()
            }
            Button {
                Task {
                    await composio.addMCPServer(name: serverName, url: serverURL, auth: serverAuth)
                }
            } label: {
                Text("Add and tag")
            }
            .disabled(composio.busySlug != nil || serverName.trimmingCharacters(in: .whitespaces).isEmpty)
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.dialogInset)
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

    private var untagBinding: Binding<Bool> {
        Binding(get: { pendingUntag != nil }, set: { if !$0 { pendingUntag = nil } })
    }
}

private enum Page: String, CaseIterable, Identifiable {
    case apps
    case mcpServer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .apps: return "Apps"
        case .mcpServer: return "MCP server"
        }
    }
}

private struct ComposioToolkitCard: View {
    let toolkit: ComposioToolkit
    let connection: ComposioConnection?
    let isConnected: Bool
    let isBusy: Bool
    let onConnect: () -> Void
    let onTag: () -> Void
    let onUntag: () -> Void

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
            HStack(spacing: Theme.Spacing.sm) {
                tagButton
                connectControl
            }
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
        .background(
            Theme.Colors.controlSurface,
            in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private var tagButton: some View {
        Button(action: connection == nil ? onTag : onUntag) {
            Label(connection == nil ? "Tag" : "@\(connection?.tag ?? "")", systemImage: "tag")
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .disabled(isBusy)
        .accessibilityLabel(
            connection == nil ? "Tag \(toolkit.name)" : "Tagged \(toolkit.name) as @\(connection?.tag ?? "")")
    }

    @ViewBuilder private var connectControl: some View {
        if toolkit.noAuth {
            Text("No sign-in")
                .font(.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        } else if isConnected {
            Text("Connected")
                .font(.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        } else {
            Button("Connect", action: onConnect)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isBusy)
                .accessibilityLabel("Connect \(toolkit.name)")
        }
    }
}
