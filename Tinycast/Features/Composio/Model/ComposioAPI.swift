import Foundation

/// Composio's current REST API. The project key travels only to a `composio.dev` host.
enum ComposioAPI {
    static let baseURL = URL(string: "https://backend.composio.dev/api/v3.1")!
    static let catalogLimit = 48

    struct Failure: LocalizedError, Equatable {
        var message: String
        var errorDescription: String? { message }
    }

    static func allowsCredential(on urlString: String) -> Bool {
        guard let url = URL(string: urlString), url.scheme == "https",
            let host = url.host()?.lowercased()
        else { return false }
        return host == "composio.dev" || host.hasSuffix(".composio.dev")
    }

    /// Composio calls this URL itself, so a loopback Tinycast would accept still cannot work.
    static func validateMCPURL(_ value: String) throws -> URL {
        let url: URL
        do {
            url = try AIEndpointPolicy.validate(value)
        } catch AIEndpointPolicy.ValidationError.insecureRemoteURL {
            throw Failure(message: "A remote MCP server has to use HTTPS.")
        } catch {
            throw Failure(message: "Enter the server's HTTPS address.")
        }
        guard !AIEndpointPolicy.isLoopback(value) else {
            throw Failure(
                message: "Composio reaches this server from the internet, so it needs a public HTTPS address.")
        }
        return url
    }

    static func httpsURL(_ string: String?) -> URL? {
        guard let string, let url = URL(string: string), url.scheme == "https" else { return nil }
        return url
    }

    static func customSlug(from name: String) -> String {
        var slug = ""
        var pendingSeparator = false
        for character in name.uppercased() {
            if character.isLetter || character.isNumber {
                if pendingSeparator, !slug.isEmpty { slug.append("_") }
                pendingSeparator = false
                slug.append(character)
            } else {
                pendingSeparator = true
            }
            if slug.count >= MCPSlug.maxLength { break }
        }
        return slug.isEmpty ? "SERVER" : slug
    }

    /// The readable name a pasted MCP address gets when the reader does not type one.
    static func displayName(for mcpURL: URL) -> String {
        guard var host = mcpURL.host()?.lowercased(), !host.isEmpty else { return "Server" }
        for prefix in ["www.", "mcp."] where host.hasPrefix(prefix) {
            host.removeFirst(prefix.count)
        }
        let label = host.split(separator: ".").first.map(String.init) ?? ""
        guard let first = label.first else { return "Server" }
        return first.uppercased() + label.dropFirst()
    }

    static func oauthDiscoveryURL(for mcpURL: URL) -> String? {
        guard var components = URLComponents(url: mcpURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.path = "/.well-known/oauth-authorization-server"
        components.query = nil
        components.fragment = nil
        return components.string
    }

    static func toolkitsURL(search: String) -> URL? {
        guard var components = URLComponents(url: baseURL.appending(path: "toolkits"), resolvingAgainstBaseURL: false)
        else { return nil }
        var items = [URLQueryItem(name: "limit", value: String(catalogLimit))]
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            items.append(URLQueryItem(name: "sort_by", value: "usage"))
        } else {
            items.append(URLQueryItem(name: "search", value: query))
        }
        components.queryItems = items
        return components.url
    }

    static func sessionURL() -> URL { baseURL.appending(path: "tool_router/session") }

    static func linkURL(sessionID: String) -> URL {
        baseURL
            .appending(path: "tool_router/session")
            .appending(path: sessionID)
            .appending(path: "link")
    }

    static func accountsURL(userID: String) -> URL? {
        guard var components = URLComponents(
            url: baseURL.appending(path: "connected_accounts"), resolvingAgainstBaseURL: false)
        else { return nil }
        components.queryItems = [
            URLQueryItem(name: "user_ids", value: userID),
            URLQueryItem(name: "statuses", value: "ACTIVE"),
            URLQueryItem(name: "limit", value: "100"),
        ]
        return components.url
    }

    static func sessionBody(userID: String, toolkitSlug: String) throws -> Data {
        let object: [String: Any] = [
            "user_id": userID,
            "toolkits": ["enable": [toolkitSlug]],
            "manage_connections": [
                "enable": true,
                "enable_connection_removal": false,
            ],
            "workbench": ["enable": false],
        ]
        return try JSONSerialization.data(withJSONObject: object)
    }

    static func linkBody(toolkitSlug: String) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["toolkit": toolkitSlug])
    }

    static func customToolkitBody(
        slug: String, name: String, appURL: String, auth: ComposioMCPAuth, discoveryURL: String?
    ) throws -> Data {
        var scheme: [String: Any] = ["mode": auth.wireMode]
        switch auth {
        case .none: break
        case .apiKey:
            scheme["headers"] = ["Authorization": "Bearer {{generic_api_key}}"]
        case .oauth:
            scheme["discovery_url"] = discoveryURL ?? ""
        }
        let object: [String: Any] = [
            "slug": slug,
            "toolkit_config": [
                "name": name,
                "app_url": appURL,
                "auth_schemes": [scheme],
            ],
        ]
        return try JSONSerialization.data(withJSONObject: object)
    }

    static func syncBody(slug: String) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["slug": slug])
    }

    static func toolkits(from data: Data) throws -> [ComposioToolkit] {
        try JSONDecoder().decode(ToolkitPage.self, from: data).items
    }

    static func session(from data: Data) throws -> ComposioSessionEndpoint {
        let decoded = try JSONDecoder().decode(SessionResponse.self, from: data)
        guard !decoded.sessionID.isEmpty, !decoded.mcp.url.isEmpty else {
            throw Failure(message: "Composio did not return a session.")
        }
        return ComposioSessionEndpoint(sessionID: decoded.sessionID, mcpURL: decoded.mcp.url)
    }

    static func connectLink(from data: Data) throws -> URL {
        let decoded = try JSONDecoder().decode(LinkResponse.self, from: data)
        guard let url = URL(string: decoded.redirectURL), allowsCredential(on: decoded.redirectURL) else {
            throw Failure(message: "Composio returned an unexpected sign-in address.")
        }
        return url
    }

    static func activeSlugs(from data: Data) throws -> Set<String> {
        Set(try JSONDecoder().decode(AccountPage.self, from: data).items.compactMap(\.activeSlug))
    }

    static func customSlug(from data: Data) throws -> String {
        let decoded = try JSONDecoder().decode(CustomToolkitResponse.self, from: data)
        guard !decoded.slug.isEmpty else {
            throw Failure(message: "Composio did not register that server.")
        }
        return decoded.slug
    }

    static func message(from data: Data, status: Int) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "Composio returned \(status)."
        }
        if let message = object["message"] as? String, !message.isEmpty { return message }
        if let error = object["error"] as? [String: Any],
            let message = error["message"] as? String, !message.isEmpty
        {
            return message
        }
        if let error = object["error"] as? String, !error.isEmpty { return error }
        return "Composio returned \(status)."
    }
}

struct ComposioToolkit: Equatable, Identifiable, Sendable {
    var slug: String
    var name: String
    var noAuth: Bool
    var description: String
    var logoURL: String?

    var id: String { slug }
}

struct ComposioSessionEndpoint: Equatable, Sendable {
    var sessionID: String
    var mcpURL: String

    var acceptsCredential: Bool { ComposioAPI.allowsCredential(on: mcpURL) }
}

enum ComposioMCPAuth: String, CaseIterable, Identifiable, Sendable {
    case none
    case apiKey
    case oauth

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "No sign-in"
        case .apiKey: return "API key"
        case .oauth: return "OAuth"
        }
    }

    var wireMode: String {
        switch self {
        case .none: return "NO_AUTH"
        case .apiKey: return "API_KEY"
        case .oauth: return "DCR_OAUTH"
        }
    }
}

private struct ToolkitPage: Decodable {
    var items: [ComposioToolkit]
}

extension ComposioToolkit: Decodable {
    private enum CodingKeys: String, CodingKey {
        case slug
        case name
        case noAuth = "no_auth"
        case meta
    }

    private struct Meta: Decodable {
        var description: String?
        var logo: String?
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        slug = try container.decode(String.self, forKey: .slug)
        name = try container.decode(String.self, forKey: .name)
        noAuth = try container.decodeIfPresent(Bool.self, forKey: .noAuth) ?? false
        let meta = try container.decodeIfPresent(Meta.self, forKey: .meta)
        description = meta?.description ?? ""
        let logo = meta?.logo?.trimmingCharacters(in: .whitespacesAndNewlines)
        logoURL = logo?.isEmpty == false ? logo : nil
    }
}

private struct SessionResponse: Decodable {
    var sessionID: String
    var mcp: MCPServerURL

    struct MCPServerURL: Decodable {
        var url: String
    }

    private enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case mcp
    }
}

private struct LinkResponse: Decodable {
    var redirectURL: String

    private enum CodingKeys: String, CodingKey {
        case redirectURL = "redirect_url"
    }
}

private struct AccountPage: Decodable {
    var items: [Item]

    struct Item: Decodable {
        var status: String
        var slug: String?

        var activeSlug: String? {
            guard status.uppercased() == "ACTIVE" else { return nil }
            return slug
        }

        private enum CodingKeys: String, CodingKey {
            case status
            case toolkit
            case toolkitSlug = "toolkit_slug"
        }

        private struct Toolkit: Decodable {
            var slug: String
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            status = try container.decodeIfPresent(String.self, forKey: .status) ?? ""
            slug =
                try container.decodeIfPresent(Toolkit.self, forKey: .toolkit)?.slug
                ?? container.decodeIfPresent(String.self, forKey: .toolkitSlug)
        }
    }
}

private struct CustomToolkitResponse: Decodable {
    var slug: String
}
