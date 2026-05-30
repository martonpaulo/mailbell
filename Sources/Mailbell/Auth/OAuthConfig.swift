import Foundation

/// OAuth client configuration. For a desktop/installed app the client secret is
/// not actually confidential (see docs/design.md), but Google still issues one
/// and expects it in the token exchange.
struct OAuthConfig {
    let clientID: String
    let clientSecret: String?

    /// Restricted full-mail scope is required for Gmail IMAP. `openid email` lets
    /// us learn the account address for the XOAUTH2 SASL string.
    let scopes = ["https://mail.google.com/", "openid", "email"]

    let authEndpoint = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!
    let userInfoEndpoint = URL(string: "https://openidconnect.googleapis.com/v1/userinfo")!

    var scopeString: String { scopes.joined(separator: " ") }

    private static let clientIDKey = "mailbell.clientID"
    private static let secretAccount = "google.clientSecret"

    /// Loads configuration, preferring values saved in the app (Settings) and
    /// falling back to environment variables (useful for `swift run`). Returns nil
    /// if unconfigured so the UI can prompt the user.
    static func load() -> OAuthConfig? {
        if let id = persistedClientID, !id.isEmpty {
            return OAuthConfig(clientID: id, clientSecret: persistedClientSecret)
        }
        return fromEnvironment()
    }

    static func fromEnvironment() -> OAuthConfig? {
        guard let clientID = ProcessInfo.processInfo.environment["MAILBELL_CLIENT_ID"],
              !clientID.isEmpty else {
            return nil
        }
        let secret = ProcessInfo.processInfo.environment["MAILBELL_CLIENT_SECRET"]
        return OAuthConfig(clientID: clientID, clientSecret: secret?.isEmpty == true ? nil : secret)
    }

    // MARK: - Persistence (entered via Settings)

    static var persistedClientID: String? {
        UserDefaults.standard.string(forKey: clientIDKey)
    }

    /// Stored in Keychain. The desktop client secret is not truly confidential
    /// (see docs/design.md), but Keychain keeps it out of plaintext anyway.
    static var persistedClientSecret: String? {
        Keychain.get(account: secretAccount)
    }

    static func save(clientID: String, clientSecret: String?) {
        let trimmedID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(trimmedID, forKey: clientIDKey)

        let trimmedSecret = clientSecret?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let secret = trimmedSecret, !secret.isEmpty {
            try? Keychain.set(secret, account: secretAccount)
        } else {
            Keychain.delete(account: secretAccount)
        }
    }
}
