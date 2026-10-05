// Composio's catalog, session, and the server a tag becomes. No network.

import Foundation

@main
@MainActor
struct ComposioTests {
    static var failures = 0
    static var passes = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func main() {
        credentialsStayOnComposioHosts()
        remoteMCPAddressesArePublicHTTPS()
        customSlugsAreToolkitIdentifiers()
        catalogDecodesTheLogoAndSkipsABlankOne()
        sessionAndLinkDecodeAndRefuseAForeignHost()
        activeAccountsIgnoreEverythingElse()
        aSessionAsksForOneToolkitAndNoWorkbench()
        aTagBecomesOneHTTPServer()
        aForeignSessionURLIsNotAServer()
        connectionsAndTheUserIDRoundTrip()

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    static func credentialsStayOnComposioHosts() {
        expect(ComposioAPI.allowsCredential(on: "https://backend.composio.dev/v3/mcp"), "the API host")
        expect(ComposioAPI.allowsCredential(on: "https://connect.composio.dev/link/abc"), "a subdomain")
        expect(ComposioAPI.allowsCredential(on: "https://composio.dev/mcp"), "the apex")
        expect(!ComposioAPI.allowsCredential(on: "http://backend.composio.dev/mcp"), "plain HTTP")
        expect(!ComposioAPI.allowsCredential(on: "https://evil.com/mcp"), "another host")
        expect(!ComposioAPI.allowsCredential(on: "https://composio.dev.evil.com/mcp"), "a suffix trick")
        expect(!ComposioAPI.allowsCredential(on: "https://notcomposio.dev/mcp"), "a lookalike apex")
        expect(ComposioAPI.httpsURL("http://cdn.example.com/a.png") == nil, "a logo has to be HTTPS")
        expect(
            ComposioAPI.httpsURL("https://cdn.example.com/a.png")?.host == "cdn.example.com",
            "an HTTPS logo is kept")
    }

    static func remoteMCPAddressesArePublicHTTPS() {
        expect(
            (try? ComposioAPI.validateMCPURL("https://mcp.example.com/mcp")) != nil,
            "a public HTTPS server is accepted")
        expect(message(of: "http://mcp.example.com/mcp") == "A remote MCP server has to use HTTPS.", "plain HTTP")
        expect(message(of: "notaurl") == "Enter the server's HTTPS address.", "a typo")
        expect(
            message(of: "http://127.0.0.1:3000/mcp")?.contains("public HTTPS") == true,
            "loopback is refused because Composio cannot reach this Mac")
        expect(
            message(of: "https://localhost/mcp")?.contains("public HTTPS") == true,
            "localhost over HTTPS is still this Mac")
    }

    static func message(of value: String) -> String? {
        do {
            _ = try ComposioAPI.validateMCPURL(value)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    static func customSlugsAreToolkitIdentifiers() {
        expect(ComposioAPI.customSlug(from: "Acme Files") == "ACME_FILES", "words become one slug")
        expect(ComposioAPI.customSlug(from: "  ") == "SERVER", "an empty name still has a slug")
        expect(!ComposioAPI.customSlug(from: "Hello!!!World").contains("!"), "punctuation is not a slug")
        guard let sample = URL(string: "https://mcp.example.com/mcp?x=1") else {
            expect(false, "the sample URL")
            return
        }
        let discovery = ComposioAPI.oauthDiscoveryURL(for: sample)
        expect(
            discovery == "https://mcp.example.com/.well-known/oauth-authorization-server",
            "discovery is the server's origin, not its MCP path")
    }

    static func catalogDecodesTheLogoAndSkipsABlankOne() {
        let data = Data(
            """
            {"items":[
              {"slug":"gmail","name":"Gmail","no_auth":false,"meta":{"description":"Mail","logo":"https://cdn.example/g.png"}},
              {"slug":"hackernews","name":"Hacker News","meta":{"logo":"  "}}
            ]}
            """.utf8)
        let items = try? ComposioAPI.toolkits(from: data)
        expect(items?.count == 2, "both toolkits decode")
        expect(items?.first?.logoURL == "https://cdn.example/g.png", "the logo is the nested one")
        expect(items?.first?.description == "Mail", "the description is nested too")
        expect(items?.last?.noAuth == false, "a missing no_auth is not no-auth")
        expect(items?.last?.logoURL == nil, "a blank logo is absent")
    }

    static func sessionAndLinkDecodeAndRefuseAForeignHost() {
        let session = try? ComposioAPI.session(
            from: Data(#"{"session_id":"trs_1","mcp":{"type":"http","url":"https://backend.composio.dev/mcp"}}"#.utf8))
        expect(session?.sessionID == "trs_1", "the session id")
        expect(session?.acceptsCredential == true, "its MCP URL may carry the key")

        let foreign = try? ComposioAPI.session(
            from: Data(#"{"session_id":"trs_2","mcp":{"url":"https://evil.example/mcp"}}"#.utf8))
        expect(foreign?.acceptsCredential == false, "a foreign MCP URL is decoded and then refused")

        let link = try? ComposioAPI.connectLink(
            from: Data(#"{"redirect_url":"https://connect.composio.dev/link/ln_1","connected_account_id":"ca_1"}"#.utf8))
        expect(link?.host == "connect.composio.dev", "the sign-in link")
        let rejected = try? ComposioAPI.connectLink(
            from: Data(#"{"redirect_url":"https://evil.example/link"}"#.utf8))
        expect(rejected == nil, "a sign-in link on another host is refused")
    }

    static func activeAccountsIgnoreEverythingElse() {
        let data = Data(
            """
            {"items":[
              {"status":"ACTIVE","toolkit":{"slug":"gmail"}},
              {"status":"INITIATED","toolkit":{"slug":"slack"}},
              {"status":"ACTIVE","toolkit_slug":"github"}
            ]}
            """.utf8)
        let slugs = try? ComposioAPI.activeSlugs(from: data)
        expect(slugs == ["github", "gmail"], "only active accounts, from either slug shape")
    }

    static func aSessionAsksForOneToolkitAndNoWorkbench() {
        guard let data = try? ComposioAPI.sessionBody(userID: "user-1", toolkitSlug: "gmail"),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            expect(false, "a session body encodes")
            return
        }
        let toolkits = object["toolkits"] as? [String: Any]
        expect(toolkits?["enable"] as? [String] == ["gmail"], "the session is that one toolkit")
        let manage = object["manage_connections"] as? [String: Any]
        expect(manage?["enable"] as? Bool == true, "the agent can still start a sign-in")
        expect(manage?["enable_connection_removal"] as? Bool == false, "removing a connection stays in Settings")
        let workbench = object["workbench"] as? [String: Any]
        expect(workbench?["enable"] as? Bool == false, "the remote workbench stays off")

        guard let custom = try? ComposioAPI.customToolkitBody(
            slug: "ACME", name: "Acme", appURL: "https://mcp.example.com/mcp", auth: .apiKey, discoveryURL: nil),
            let customObject = try? JSONSerialization.jsonObject(with: custom) as? [String: Any],
            let config = customObject["toolkit_config"] as? [String: Any],
            let schemes = config["auth_schemes"] as? [[String: Any]]
        else {
            expect(false, "a custom server body encodes")
            return
        }
        expect(schemes.first?["mode"] as? String == "API_KEY", "an API key server says so")
        let headers = schemes.first?["headers"] as? [String: String]
        expect(headers?["Authorization"]?.contains("{{generic_api_key}}") == true, "the key is a placeholder")
    }

    static func aTagBecomesOneHTTPServer() {
        let connection = ComposioConnection(
            id: UUID(), toolkitSlug: "gmail", name: "Gmail", tag: "gmail", logoURL: nil,
            sessionID: "trs_1", sessionMCPURL: "https://backend.composio.dev/mcp", kind: .app)
        let server = ComposioServerProjection.server(from: connection)
        expect(server?.id == connection.id, "the tag and the server are the same row")
        expect(server?.slug == "gmail", "the tag is the handle")
        expect(server?.trust == .ask, "a new tag asks")
        guard case .http(let url, let header) = server?.transport else {
            expect(false, "the session is an HTTP server")
            return
        }
        expect(url == connection.sessionMCPURL, "chat calls the session URL")
        expect(header == ComposioServerProjection.headerName, "the header is the project key's name")

        let kept = MCPServer(
            id: connection.id, name: "Gmail", slug: "gmail",
            transport: .http(url: "old", headerName: "Authorization"), isEnabled: false, trust: .always)
        let refreshed = ComposioServerProjection.server(from: connection, preserving: kept)
        expect(refreshed?.trust == .always && refreshed?.isEnabled == false, "a refresh keeps the reader's choices")
    }

    static func aForeignSessionURLIsNotAServer() {
        let connection = ComposioConnection(
            id: UUID(), toolkitSlug: "gmail", name: "Gmail", tag: "gmail", logoURL: nil,
            sessionID: "trs_1", sessionMCPURL: "https://evil.example/mcp", kind: .app)
        expect(ComposioServerProjection.server(from: connection) == nil, "the key is not attached to another host")
    }

    static func connectionsAndTheUserIDRoundTrip() {
        let suite = "composio-test-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            expect(false, "a private defaults suite")
            return
        }
        let store = ComposioConnectionsStore(defaults: defaults)
        expect(!store.userID.isEmpty, "this Mac has an id")
        let again = ComposioConnectionsStore(defaults: defaults)
        expect(again.userID == store.userID, "the id is kept")
        let connection = ComposioConnection(
            id: UUID(), toolkitSlug: "CUSTOM_ACME", name: "Acme", tag: "acme", logoURL: nil,
            sessionID: "trs_9", sessionMCPURL: "https://backend.composio.dev/mcp", kind: .mcpServer)
        store.upsert(connection)
        let loaded = ComposioConnectionsStore(defaults: defaults)
        expect(loaded.connection(toolkitSlug: "CUSTOM_ACME") == connection, "a tag survives a relaunch")
        loaded.remove(id: connection.id)
        expect(ComposioConnectionsStore(defaults: defaults).connections.isEmpty, "removing a tag forgets it")
        defaults.removePersistentDomain(forName: suite)
    }
}
