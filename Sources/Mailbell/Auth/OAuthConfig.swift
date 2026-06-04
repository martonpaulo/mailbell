import Foundation

struct OAuthConfig {
    let clientID: String
    let clientSecret: String

    let scopes = ["https://mail.google.com/", "openid", "email"]

    let authEndpoint = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!
    let userInfoEndpoint = URL(string: "https://openidconnect.googleapis.com/v1/userinfo")!

    var scopeString: String { scopes.joined(separator: " ") }

    private static let clientIDKey = "MAILBELL_GOOGLE_CLIENT_ID"
    private static let clientSecretKey = "MAILBELL_GOOGLE_CLIENT_SECRET"
    private static let bundleClientIDKey = "MailbellGoogleClientID"
    private static let bundleClientSecretKey = "MailbellGoogleClientSecret"

    static func load() -> OAuthConfig? {
        fromBundle() ?? fromEnvironment(ProcessInfo.processInfo.environment) ?? fromDotEnv()
    }

    private static func fromBundle() -> OAuthConfig? {
        guard let clientID = Bundle.main.object(forInfoDictionaryKey: bundleClientIDKey) as? String,
              let clientSecret = Bundle.main.object(forInfoDictionaryKey: bundleClientSecretKey) as? String else {
            return nil
        }
        return make(clientID: clientID, clientSecret: clientSecret)
    }

    private static func fromEnvironment(_ environment: [String: String]) -> OAuthConfig? {
        make(clientID: environment[clientIDKey], clientSecret: environment[clientSecretKey])
    }

    private static func fromDotEnv() -> OAuthConfig? {
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".env")
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let values = content
            .split(whereSeparator: \.isNewline)
            .reduce(into: [String: String]()) { result, line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), let separator = trimmed.firstIndex(of: "=") else {
                    return
                }
                let key = String(trimmed[..<separator]).trimmingCharacters(in: .whitespaces)
                let rawValue = String(trimmed[trimmed.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
                result[key] = rawValue.strippingMatchingQuotes()
            }
        return fromEnvironment(values)
    }

    private static func make(clientID: String?, clientSecret: String?) -> OAuthConfig? {
        guard let clientID = clientID?.trimmingCharacters(in: .whitespacesAndNewlines),
              let clientSecret = clientSecret?.trimmingCharacters(in: .whitespacesAndNewlines),
              !clientID.isEmpty,
              !clientSecret.isEmpty else {
            return nil
        }
        return OAuthConfig(clientID: clientID, clientSecret: clientSecret)
    }
}

private extension String {
    func strippingMatchingQuotes() -> String {
        guard count >= 2,
              let first,
              let last,
              (first == "\"" && last == "\"") || (first == "'" && last == "'") else {
            return self
        }
        return String(dropFirst().dropLast())
    }
}
