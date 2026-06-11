import Foundation

struct KeychainClient {
    let set: @Sendable (_ value: String, _ account: String) throws -> Void
    let get: @Sendable (_ account: String) -> String?
    let delete: @Sendable (_ account: String) -> Void

    static let live = KeychainClient(
        set: { value, account in try Keychain.set(value, account: account) },
        get: { account in Keychain.get(account: account) },
        delete: { account in Keychain.delete(account: account) }
    )
}

/// Persists one account's OAuth session.
///
/// - The refresh token lives in the Keychain as part of one account-scoped session item.
/// - The short-lived access token and expiry are cached in that same item so a
///   relaunch can reuse a still-valid access token without extra Keychain prompts.
final class TokenStore {
    enum TokenStoreError: Error, LocalizedError {
        case encodingFailed

        var errorDescription: String? {
            switch self {
            case .encodingFailed:
                "Could not encode OAuth tokens for Keychain storage."
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
        keychain.get(sessionAccount) != nil
    }

    func save(tokens: GoogleTokens) throws {
        let previousSession = keychain.get(sessionAccount)

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

    func loadTokens() -> GoogleTokens? {
        guard let json = keychain.get(sessionAccount),
              let data = json.data(using: .utf8),
              let tokens = try? JSONDecoder().decode(GoogleTokens.self, from: data)
        else {
            return nil
        }
        return tokens
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
            Log.error("Failed to restore \(label) token after save failure: \(error.localizedDescription)")
        }
    }
}
