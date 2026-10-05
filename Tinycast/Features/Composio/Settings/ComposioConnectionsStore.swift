import Foundation
import Observation

/// The apps and remote MCP servers this Mac has tagged. The API key is not here.
@MainActor
@Observable
final class ComposioConnectionsStore {
    private let defaults: UserDefaults
    let userID: String

    private(set) var connections: [ComposioConnection] {
        didSet { persist() }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let stored = defaults.string(forKey: AppSettingsKey.composioUserID.rawValue), !stored.isEmpty {
            userID = stored
        } else {
            let created = UUID().uuidString.lowercased()
            defaults.set(created, forKey: AppSettingsKey.composioUserID.rawValue)
            userID = created
        }
        connections = Self.decode(defaults.data(forKey: AppSettingsKey.composioConnections.rawValue))
    }

    func connection(id: UUID) -> ComposioConnection? {
        connections.first { $0.id == id }
    }

    func connection(toolkitSlug: String) -> ComposioConnection? {
        connections.first { $0.toolkitSlug == toolkitSlug }
    }

    func upsert(_ connection: ComposioConnection) {
        if let index = connections.firstIndex(where: { $0.id == connection.id }) {
            connections[index] = connection
        } else {
            connections.append(connection)
        }
    }

    func remove(id: UUID) {
        connections.removeAll { $0.id == id }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(connections) else { return }
        defaults.set(data, forKey: AppSettingsKey.composioConnections.rawValue)
    }

    private static func decode(_ data: Data?) -> [ComposioConnection] {
        guard let data, let connections = try? JSONDecoder().decode([ComposioConnection].self, from: data)
        else { return [] }
        return connections
    }
}
