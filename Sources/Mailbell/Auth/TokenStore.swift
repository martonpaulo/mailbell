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
/// - The refresh token lives in the Keychain.
/// - The (short-lived) access token + expiry are cached in the Keychain too so a
///   relaunch can reuse a still-valid access token instead of forcing a refresh.
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

    private let refreshAccount: String
    private let accessAccount: String
    private let keychain: KeychainClient

    init(
        accountID: UUID,
        providerID: MailProviderID = .gmail,
        keychain: KeychainClient = .live
    ) {
        let namespace = "mailbell.account.\(accountID.uuidString).\(providerID.rawValue)"
        refreshAccount = "\(namespace).refreshToken"
        accessAccount = "\(namespace).accessToken"
        self.keychain = keychain
    }

    var hasSession: Bool {
        keychain.get(refreshAccount) != nil
    }

    func save(tokens: GoogleTokens) throws {
        let previousRefresh = keychain.get(refreshAccount)
        let previousAccess = keychain.get(accessAccount)

        do {
            if let refresh = tokens.refreshToken {
                try keychain.set(refresh, refreshAccount)
            }
            let data = try JSONEncoder().encode(tokens)
            guard let json = String(data: data, encoding: .utf8) else {
                throw TokenStoreError.encodingFailed
            }
            try keychain.set(json, accessAccount)
        } catch {
            restoreToken(previousRefresh, account: refreshAccount, label: "refresh")
            restoreToken(previousAccess, account: accessAccount, label: "access")
            throw error
        }
    }

    func loadTokens() -> GoogleTokens? {
        guard let json = keychain.get(accessAccount),
              let data = json.data(using: .utf8),
              var tokens = try? JSONDecoder().decode(GoogleTokens.self, from: data)
        else {
            // Fall back to a bare refresh token if the cached access token is gone.
            guard let refresh = keychain.get(refreshAccount) else { return nil }
            return GoogleTokens(accessToken: "", refreshToken: refresh, expiresAt: .distantPast)
        }
        if tokens.refreshToken == nil {
            tokens.refreshToken = keychain.get(refreshAccount)
        }
        return tokens
    }

    func clear() {
        keychain.delete(refreshAccount)
        keychain.delete(accessAccount)
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
