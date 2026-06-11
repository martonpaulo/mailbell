import Foundation

struct OAuthConfig {
    let clientID: String
    let clientSecret: String

    let scopes = ["https://mail.google.com/", "openid", "email"]

    let authEndpoint = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!
    let userInfoEndpoint = URL(string: "https://openidconnect.googleapis.com/v1/userinfo")!

    var scopeString: String {
        scopes.joined(separator: " ")
    }

    static let clientIDKey = "MAILBELL_GOOGLE_CLIENT_ID"
    static let clientSecretKey = "MAILBELL_GOOGLE_CLIENT_SECRET"
    static let bundleClientIDKey = "MailbellGoogleClientID"
    static let bundleClientSecretKey = "MailbellGoogleClientSecret"

    static func load() -> OAuthConfig? {
        try? loadOrThrow()
    }

    static func loadOrThrow() throws -> OAuthConfig {
        try load(
            bundleClientID: Bundle.main.object(forInfoDictionaryKey: bundleClientIDKey) as? String,
            bundleClientSecret: Bundle.main.object(forInfoDictionaryKey: bundleClientSecretKey) as? String,
            environment: ProcessInfo.processInfo.environment,
            dotEnv: readDotEnv()
        )
    }

    static func load(
        bundleClientID: String? = nil,
        bundleClientSecret: String? = nil,
        environment: [String: String],
        dotEnv: [String: String] = [:]
    ) throws -> OAuthConfig {
        if hasAnyValue(clientID: bundleClientID, clientSecret: bundleClientSecret) {
            return try make(clientID: bundleClientID, clientSecret: bundleClientSecret)
        }

        let environmentClientID = environment[clientIDKey]
        let environmentClientSecret = environment[clientSecretKey]
        if hasAnyValue(clientID: environmentClientID, clientSecret: environmentClientSecret) {
            return try make(clientID: environmentClientID, clientSecret: environmentClientSecret)
        }

        let dotEnvClientID = dotEnv[clientIDKey]
        let dotEnvClientSecret = dotEnv[clientSecretKey]
        if hasAnyValue(clientID: dotEnvClientID, clientSecret: dotEnvClientSecret) {
            return try make(clientID: dotEnvClientID, clientSecret: dotEnvClientSecret)
        }

        throw OAuthConfigIssue.missingCredentials
    }

    static func configurationIssue() -> OAuthConfigIssue? {
        do {
            _ = try loadOrThrow()
            return nil
        } catch let issue as OAuthConfigIssue {
            return issue
        } catch {
            return .invalidCredentials
        }
    }

    private static func readDotEnv() -> [String: String] {
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".env")
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        return content
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
    }

    private static func hasAnyValue(clientID: String?, clientSecret: String?) -> Bool {
        let clientID = clientID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let clientSecret = clientSecret?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !clientID.isEmpty || !clientSecret.isEmpty
    }

    private static func make(clientID: String?, clientSecret: String?) throws -> OAuthConfig {
        guard let clientID = clientID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !clientID.isEmpty,
              let clientSecret = clientSecret?.trimmingCharacters(in: .whitespacesAndNewlines),
              !clientSecret.isEmpty
        else {
            throw OAuthConfigIssue.missingCredentials
        }
        guard clientID.hasSuffix(".apps.googleusercontent.com") else {
            throw OAuthConfigIssue.invalidClientID
        }
        return OAuthConfig(clientID: clientID, clientSecret: clientSecret)
    }
}

enum OAuthConfigIssue: Error, Equatable, LocalizedError {
    case missingCredentials
    case invalidClientID
    case invalidCredentials

    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            "Google OAuth setup is required. Set MAILBELL_GOOGLE_CLIENT_ID and "
                + "MAILBELL_GOOGLE_CLIENT_SECRET in .env or your shell, then rebuild or reinstall Mailbell. "
                + "See README > Google sign-in."
        case .invalidClientID:
            "Google OAuth client ID looks invalid. Use your Desktop OAuth client ID ending in "
                + ".apps.googleusercontent.com. See README > Google sign-in."
        case .invalidCredentials:
            "Google OAuth credentials are invalid. Check your local .env or shell values and reinstall Mailbell."
        }
    }
}

private extension String {
    func strippingMatchingQuotes() -> String {
        guard count >= 2,
              let first,
              let last,
              (first == "\"" && last == "\"") || (first == "'" && last == "'")
        else {
            return self
        }
        return String(dropFirst().dropLast())
    }
}
