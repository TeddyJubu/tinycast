import Foundation

/// The Composio project key, one login-Keychain item. It never enters preferences or a backup.
enum ComposioSecretStore {
    static let account = UUID(uuidString: "C0A10510-4E00-4000-8000-000000000001")!
    private static let keychain = KeychainSecretStore(scope: "composio-api-key")

    static func apiKey() throws -> String? {
        let stored = try keychain.secret(for: account)
        guard let stored, !stored.isEmpty else { return nil }
        return stored
    }

    static func hasAPIKey() throws -> Bool {
        try keychain.hasSecret(for: account)
    }

    static func setAPIKey(_ key: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            try keychain.removeSecret(for: account)
            return
        }
        try keychain.setSecret(trimmed, for: account)
    }

    static func removeAPIKey() throws {
        try keychain.removeSecret(for: account)
    }
}
