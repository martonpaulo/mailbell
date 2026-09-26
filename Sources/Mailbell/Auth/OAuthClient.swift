import AppKit
import CryptoKit
import Foundation
import MailbellKit

/// Implements Google's installed-app OAuth flow with PKCE over a loopback redirect.
/// Also handles access-token refresh and fetching the account email.
///
/// Nonisolated: refreshes inside MailMonitor run tasks; only openBrowser hops to the main actor.
nonisolated final class OAuthClient {
    enum OAuthError: Error, Equatable, LocalizedError {
        case browserOpenFailed
        case authorizationDenied(String)
        case missingCode
        case tokenExchangeFailed(String)
        case refreshFailed(String)
        case refreshUnavailable(String)
        case noRefreshToken
        case missingEmail(String)
        case secureRandomUnavailable

        var errorDescription: String? {
            switch self {
            // The technical detail stays in the case for the log (Log.detail).
            case .browserOpenFailed: String(localized: "Couldn't open your browser to sign in.")
            case .authorizationDenied: String(localized: "Access wasn't allowed in Google. Try again and allow access.")
            case .missingCode, .tokenExchangeFailed:
                String(localized: "Google sign-in couldn't be completed. Try again.")
            case .refreshFailed: String(localized: "Google ended this sign-in. Sign in again.")
            case .refreshUnavailable:
                String(localized: "Couldn't reach Google to renew the sign-in. Mailbell will try again.")
            case .noRefreshToken: String(localized: "No saved sign-in. Sign in again.")
            case .missingEmail: String(localized: "Google didn't share the account's email address. Try again.")
            case .secureRandomUnavailable: String(localized: "Couldn't start sign-in on this Mac. Try again.")
            }
        }
    }

    struct TokenEndpointFailure: Error, LocalizedError {
        let detail: String
        let invalidGrant: Bool

        var errorDescription: String? {
            detail
        }
    }

    let config: OAuthConfig
    let session: URLSession
    private let openBrowser: @MainActor (URL) -> Bool
    private let loopbackServerFactory: () -> LoopbackServer

    static let requestTimeout: TimeInterval = 30
    static let resourceTimeout: TimeInterval = 60

    init(
        config: OAuthConfig,
        session: URLSession? = nil,
        openBrowser: @escaping @MainActor (URL) -> Bool = { NSWorkspace.shared.open($0) },
        loopbackServerFactory: @escaping () -> LoopbackServer = { LoopbackServer() }
    ) {
        self.config = config
        self.session = session ?? Self.makeSession()
        self.openBrowser = openBrowser
        self.loopbackServerFactory = loopbackServerFactory
    }

    // MARK: - Interactive sign-in

    /// Runs the full interactive flow and returns tokens plus the account email.
    func signIn() async throws -> (tokens: GoogleTokens, email: String) {
        let verifier = try Self.randomURLSafeString(count: 64)
        let challenge = Self.codeChallenge(for: verifier)
        let state = try Self.randomURLSafeString(count: 24)
        let server = loopbackServerFactory()

        do {
            try await server.start(expectedState: state)
            let redirectURI = await server.redirectURI
            Log.auth.info("OAuth redirect URI: \(Log.redact(redirectURI), privacy: .public)")

            guard var comps = URLComponents(url: config.authEndpoint, resolvingAgainstBaseURL: false) else {
                await server.stop()
                throw OAuthError.browserOpenFailed
            }
            comps.queryItems = [
                .init(name: "client_id", value: config.clientID),
                .init(name: "redirect_uri", value: redirectURI),
                .init(name: "response_type", value: "code"),
                .init(name: "scope", value: config.scopeString),
                .init(name: "code_challenge", value: challenge),
                .init(name: "code_challenge_method", value: "S256"),
                .init(name: "state", value: state),
                .init(name: "access_type", value: "offline"),
                .init(name: "prompt", value: "consent"),
            ]

            guard let authURL = comps.url else {
                await server.stop()
                throw OAuthError.browserOpenFailed
            }
            guard await openBrowser(authURL) else {
                await server.stop()
                throw OAuthError.browserOpenFailed
            }

            let callback = try await server.waitForCallback()
            let tokens = try await exchangeCode(callback.code, verifier: verifier, redirectURI: redirectURI)
            let email = try await fetchEmail(accessToken: tokens.accessToken)
            return (tokens, email)
        } catch {
            await server.stop()
            throw Self.oauthError(from: error)
        }
    }

    // MARK: - PKCE helpers

    static func randomURLSafeString(
        count: Int,
        copyRandomBytes: (Int, UnsafeMutableRawPointer) -> OSStatus = { count, buffer in
            SecRandomCopyBytes(kSecRandomDefault, count, buffer)
        }
    ) throws -> String {
        guard count > 0 else { throw OAuthError.secureRandomUnavailable }
        var bytes = [UInt8](repeating: 0, count: count)
        let status = bytes.withUnsafeMutableBytes { buffer -> OSStatus in
            guard let baseAddress = buffer.baseAddress else { return errSecParam }
            return copyRandomBytes(count, baseAddress)
        }
        guard status == errSecSuccess else {
            throw OAuthError.secureRandomUnavailable
        }
        return Data(bytes).base64URLEncodedString()
    }

    private static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncodedString()
    }

    static func urlEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

// Nonisolated: a pure helper used by OAuthClient off the main actor.
nonisolated extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
