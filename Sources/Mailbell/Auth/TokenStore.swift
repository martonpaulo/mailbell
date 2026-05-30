import Foundation

/// Persists the signed-in account email and its tokens.
///
/// - The refresh token lives in the Keychain.
/// - The (short-lived) access token + expiry are cached in the Keychain too so a
///   relaunch can reuse a still-valid access token instead of forcing a refresh.
/// - The account email is non-secret and kept in UserDefaults for quick UI access.
final class TokenStore {
    private let refreshAccount = "google.refreshToken"
    private let accessAccount = "google.accessToken"
    private let emailKey = "mailbell.accountEmail"

    private(set) var email: String? {
        didSet { UserDefaults.standard.set(email, forKey: emailKey) }
    }

    init() {
        email = UserDefaults.standard.string(forKey: emailKey)
    }

    var hasSession: Bool {
        Keychain.get(account: refreshAccount) != nil
    }

    func save(tokens: GoogleTokens, email: String) {
        self.email = email
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
        email = nil
    }
}
