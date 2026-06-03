import Foundation

/// Persists one account's OAuth session.
///
/// - The refresh token lives in the Keychain.
/// - The (short-lived) access token + expiry are cached in the Keychain too so a
///   relaunch can reuse a still-valid access token instead of forcing a refresh.
final class TokenStore {
    private static let legacyRefreshAccount = "google.refreshToken"
    private static let legacyAccessAccount = "google.accessToken"

    private let refreshAccount: String
    private let accessAccount: String

    init(accountID: UUID? = nil, providerID: MailProviderID = .gmail) {
        if let accountID {
            let namespace = "mailbell.account.\(accountID.uuidString).\(providerID.rawValue)"
            refreshAccount = "\(namespace).refreshToken"
            accessAccount = "\(namespace).accessToken"
        } else {
            refreshAccount = Self.legacyRefreshAccount
            accessAccount = Self.legacyAccessAccount
        }
    }

    var hasSession: Bool {
        Keychain.get(account: refreshAccount) != nil
    }

    func save(tokens: GoogleTokens) {
        if let refresh = tokens.refreshToken {
            try? Keychain.set(refresh, account: refreshAccount)
        }
        if let data = try? JSONEncoder().encode(tokens),
           let json = String(data: data, encoding: .utf8) {
            try? Keychain.set(json, account: accessAccount)
        }
    }

    func loadTokens() -> GoogleTokens? {
        guard let json = Keychain.get(account: accessAccount),
              let data = json.data(using: .utf8),
              var tokens = try? JSONDecoder().decode(GoogleTokens.self, from: data)
        else {
            // Fall back to a bare refresh token if the cached access token is gone.
            guard let refresh = Keychain.get(account: refreshAccount) else { return nil }
            return GoogleTokens(accessToken: "", refreshToken: refresh, expiresAt: .distantPast)
        }
        if tokens.refreshToken == nil {
            tokens.refreshToken = Keychain.get(account: refreshAccount)
        }
        return tokens
    }

    var refreshToken: String? {
        Keychain.get(account: refreshAccount)
    }

    func clear() {
        Keychain.delete(account: refreshAccount)
        Keychain.delete(account: accessAccount)
    }

    static func migrateLegacyTokens(to accountID: UUID) {
        let scoped = TokenStore(accountID: accountID)
        let scopedAlreadyExists = scoped.hasSession
        var canClearLegacyRefresh = scopedAlreadyExists
        var canClearLegacyAccess = scopedAlreadyExists

        if !scopedAlreadyExists, let refresh = Keychain.get(account: legacyRefreshAccount) {
            do {
                try Keychain.set(refresh, account: scoped.refreshAccount)
                canClearLegacyRefresh = true
            } catch {}
        }
        if !scopedAlreadyExists, let access = Keychain.get(account: legacyAccessAccount) {
            do {
                try Keychain.set(access, account: scoped.accessAccount)
                canClearLegacyAccess = true
            } catch {}
        }

        if canClearLegacyRefresh {
            Keychain.delete(account: legacyRefreshAccount)
        }
        if canClearLegacyAccess {
            Keychain.delete(account: legacyAccessAccount)
        }
    }
}
