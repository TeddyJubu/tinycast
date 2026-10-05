import Foundation

/// One app or remote MCP server the reader tagged, and the session that serves it to chat.
struct ComposioConnection: Codable, Equatable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable {
        case app
        case mcpServer
    }

    var id: UUID
    var toolkitSlug: String
    var name: String
    var tag: String
    var logoURL: String?
    var sessionID: String
    var sessionMCPURL: String
    var kind: Kind

    var title: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? toolkitSlug : trimmed
    }
}

/// A tagged connection becomes one HTTP server the chat already knows how to run.
enum ComposioServerProjection {
    static let headerName = "x-api-key"

    static func server(from connection: ComposioConnection, preserving: MCPServer? = nil) -> MCPServer? {
        guard connection.sessionID.isEmpty == false, ComposioAPI.allowsCredential(on: connection.sessionMCPURL)
        else { return nil }
        return MCPServer(
            id: connection.id, name: connection.name, slug: connection.tag,
            transport: .http(url: connection.sessionMCPURL, headerName: headerName),
            isEnabled: preserving?.isEnabled ?? true, trust: preserving?.trust ?? .ask)
    }
}
