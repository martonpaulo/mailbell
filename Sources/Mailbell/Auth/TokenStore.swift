import Foundation

// Nonisolated: its closures run inside MailMonitor run tasks.
nonisolated struct KeychainClient {
    let set: @Sendable (_ value: String, _ account: String) throws -> Void
    let get: @Sendable (_ account: String) throws -> String?
    let delete: @Sendable (_ account: String) -> Void

    static let live = KeychainClient(backend: Keychain.self)
}

/// The static Keychain API `KeychainClient` forwards to. `Keychain` is the
/// production backend; a test passes a stub to reach the same closures.
nonisolated protocol KeychainBackend: SendableMetatype {
    static func set(_ value: String, account: String) throws
    static func get(account: String) throws -> String?
    static func delete(account: String)
}

nonisolated extension Keychain: KeychainBackend {}

nonisolated extension KeychainClient {
    init<Backend: KeychainBackend>(backend _: Backend.Type) {
        self.init(
            set: { value, account in try Backend.set(value, account: account) },
            get: { account in try Backend.get(account: account) },
            delete: { account in Backend.delete(account: account) }
        )
    }
}

/// Persists one account's OAuth session.
///
/// - The refresh token lives in the Keychain as part of one account-scoped session item.
/// - The short-lived access token and expiry are cached in that same item so a
///   relaunch can reuse a still-valid access token without extra Keychain prompts.
///
/// Nonisolated: loads and saves tokens inside MailMonitor run tasks.
nonisolated final class TokenStore {
    enum TokenStoreError: Error, LocalizedError {
        case decodingFailed
        case encodingFailed

        var errorDescription: String? {
            switch self {
            case .decodingFailed:
                String(localized: "Couldn't read the saved sign-in from the Keychain. Sign in again.")
            case .encodingFailed:
                String(localized: "Couldn't save the sign-in to the Keychain. Try again.")
            }
        }
    }

    private let sessionAccount: String
    private let keychain: KeychainClient

    init(
        accountID: UUID,
        providerID: MailProviderID = .gmail,
        keychain: KeychainClient = .live
    ) {
        let namespace = "mailbell.account.\(accountID.uuidString).\(providerID.rawValue)"
        sessionAccount = "\(namespace).session"
        self.keychain = keychain
    }

    var hasSession: Bool {
        (try? hasStoredSession()) == true
    }

    func hasStoredSession() throws -> Bool {
        try keychain.get(sessionAccount) != nil
    }

    func save(tokens: GoogleTokens) throws {
        let previousSession = try keychain.get(sessionAccount)

        do {
            let data = try JSONEncoder().encode(tokens)
            guard let json = String(data: data, encoding: .utf8) else {
                throw TokenStoreError.encodingFailed
            }
            try keychain.set(json, sessionAccount)
        } catch {
            restoreToken(previousSession, account: sessionAccount, label: "session")
            throw error
        }
    }

    func loadTokens() throws -> GoogleTokens? {
        guard let json = try keychain.get(sessionAccount) else {
            return nil
        }
        guard let data = json.data(using: .utf8) else {
            throw TokenStoreError.decodingFailed
        }
        do {
            return try JSONDecoder().decode(GoogleTokens.self, from: data)
        } catch {
            throw TokenStoreError.decodingFailed
        }
    }

    func clear() {
        keychain.delete(sessionAccount)
    }

    private func restoreToken(_ value: String?, account: String, label: String) {
        do {
            if let value {
                try keychain.set(value, account)
            } else {
                keychain.delete(account)
            }
        } catch {
            Log.auth.error(
                "Failed to restore \(label, privacy: .public) token after save failure: \(Log.detail(error), privacy: .private)"
            )
        }
    }
}
