import AppKit
import CryptoKit
import Foundation

/// Implements Google's installed-app OAuth flow with PKCE over a loopback redirect.
/// Also handles access-token refresh and fetching the account email.
final class OAuthClient {
    enum OAuthError: Error, LocalizedError {
        case browserOpenFailed
        case authorizationDenied(String)
        case missingCode
        case tokenExchangeFailed(String)
        case refreshFailed(String)
        case refreshUnavailable(String)
        case noRefreshToken
        case missingEmail(String)

        var errorDescription: String? {
            switch self {
            case .browserOpenFailed: "Could not open the browser for sign-in."
            case let .authorizationDenied(detail): "Authorization denied: \(detail)"
            case .missingCode: "No authorization code was returned."
            case let .tokenExchangeFailed(detail): "Token exchange failed: \(detail)"
            case let .refreshFailed(detail): "Token refresh failed: \(detail)"
            case let .refreshUnavailable(detail): "Token refresh unavailable: \(detail)"
            case .noRefreshToken: "No refresh token is stored; sign in again."
            case let .missingEmail(detail): "Could not read the account email: \(detail)"
            }
        }
    }

    private struct TokenEndpointFailure: Error, LocalizedError {
        let detail: String
        let invalidGrant: Bool

        var errorDescription: String? {
            detail
        }
    }

    private let config: OAuthConfig
    private let session: URLSession

    private static let requestTimeout: TimeInterval = 30
    private static let resourceTimeout: TimeInterval = 60

    init(config: OAuthConfig, session: URLSession? = nil) {
        self.config = config
        self.session = session ?? Self.makeSession()
    }

    // MARK: - Interactive sign-in

    /// Runs the full interactive flow and returns tokens plus the account email.
    func signIn() async throws -> (tokens: GoogleTokens, email: String) {
        let server = LoopbackServer()
        try await server.start()
        defer { server.stop() }

        let redirectURI = server.redirectURI
        Log.info("OAuth redirect URI: \(redirectURI)")

        let verifier = Self.randomURLSafeString(count: 64)
        let challenge = Self.codeChallenge(for: verifier)
        let state = Self.randomURLSafeString(count: 24)

        var comps = URLComponents(url: config.authEndpoint, resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "client_id", value: config.clientID),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: config.scopeString),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: state),
            .init(name: "access_type", value: "offline"),
            .init(name: "prompt", value: "consent")
        ]

        guard let authURL = comps.url, NSWorkspace.shared.open(authURL) else {
            throw OAuthError.browserOpenFailed
        }

        let items = try await server.waitForCallback()
        if let error = items.first(where: { $0.name == "error" })?.value {
            throw OAuthError.authorizationDenied(error)
        }
        guard items.first(where: { $0.name == "state" })?.value == state else {
            throw OAuthError.authorizationDenied("state mismatch")
        }
        guard let code = items.first(where: { $0.name == "code" })?.value else {
            throw OAuthError.missingCode
        }

        let tokens = try await exchangeCode(code, verifier: verifier, redirectURI: redirectURI)
        let email = try await fetchEmail(accessToken: tokens.accessToken)
        return (tokens, email)
    }

    // MARK: - Token exchange / refresh

    private func exchangeCode(_ code: String, verifier: String, redirectURI: String) async throws -> GoogleTokens {
        let form: [String: String] = [
            "client_id": config.clientID,
            "client_secret": config.clientSecret,
            "code": code,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "redirect_uri": redirectURI
        ]

        do {
            let response: TokenResponse = try await postForm(config.tokenEndpoint, form: form)
            return response.tokens(existingRefreshToken: nil)
        } catch {
            throw OAuthError.tokenExchangeFailed(error.localizedDescription)
        }
    }

    /// Exchanges a refresh token for a fresh access token.
    func refresh(refreshToken: String) async throws -> GoogleTokens {
        let form: [String: String] = [
            "client_id": config.clientID,
            "client_secret": config.clientSecret,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ]

        do {
            let response: TokenResponse = try await postForm(config.tokenEndpoint, form: form)
            return response.tokens(existingRefreshToken: refreshToken)
        } catch let failure as TokenEndpointFailure {
            if failure.invalidGrant {
                throw OAuthError.refreshFailed(failure.detail)
            }
            throw OAuthError.refreshUnavailable(failure.detail)
        } catch let oauthError as OAuthError {
            throw oauthError
        } catch {
            throw Self.transientRefreshError(error)
        }
    }

    private func fetchEmail(accessToken: String) async throws -> String {
        var request = URLRequest(url: config.userInfoEndpoint)
        request.timeoutInterval = Self.requestTimeout
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200 ..< 300).contains(http.statusCode) {
            throw OAuthError.missingEmail(Self.sanitizedUserInfoDetail(statusCode: http.statusCode))
        }
        struct UserInfo: Decodable { let email: String? }
        do {
            let info = try JSONDecoder().decode(UserInfo.self, from: data)
            guard let email = info.email, !email.isEmpty else {
                throw OAuthError.missingEmail("OpenID UserInfo response did not include an email address.")
            }
            return email
        } catch let oauthError as OAuthError {
            throw oauthError
        } catch {
            throw OAuthError.missingEmail("OpenID UserInfo response could not be decoded.")
        }
    }

    private func postForm<T: Decodable>(_ url: URL, form: [String: String]) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = Self.requestTimeout
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = form
            .map { "\($0.key)=\(Self.urlEncode($0.value))" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200 ..< 300).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? "status \(http.statusCode)"
            throw TokenEndpointFailure(
                detail: Self.sanitizedTokenEndpointDetail(statusCode: http.statusCode, body: body),
                invalidGrant: Self.isInvalidGrant(body)
            )
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = resourceTimeout
        return URLSession(configuration: configuration)
    }

    private static func transientRefreshError(_ error: Error) -> OAuthError {
        if let urlError = error as? URLError, isTransientNetworkError(urlError) {
            return .refreshUnavailable(urlError.localizedDescription)
        }
        return .refreshUnavailable(error.localizedDescription)
    }

    private static func isTransientNetworkError(_ error: URLError) -> Bool {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .timedOut,
             .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed,
             .internationalRoamingOff, .dataNotAllowed, .secureConnectionFailed:
            true
        default:
            false
        }
    }

    private static func isInvalidGrant(_ body: String) -> Bool {
        struct TokenError: Decodable {
            let error: String?
        }
        if let data = body.data(using: .utf8),
           let parsed = try? JSONDecoder().decode(TokenError.self, from: data),
           parsed.error == "invalid_grant" {
            return true
        }
        return body.contains("invalid_grant")
    }

    static func sanitizedTokenEndpointDetail(statusCode: Int, body: String) -> String {
        struct TokenError: Decodable {
            let error: String?
        }
        if let data = body.data(using: .utf8),
           let parsed = try? JSONDecoder().decode(TokenError.self, from: data),
           let code = sanitizedTokenErrorCode(parsed.error),
           !code.isEmpty {
            return "OAuth token endpoint returned \(code) (HTTP \(statusCode))."
        }
        return "OAuth token endpoint returned HTTP \(statusCode)."
    }

    static func sanitizedUserInfoDetail(statusCode: Int) -> String {
        "OpenID UserInfo endpoint returned HTTP \(statusCode)."
    }

    private static func sanitizedTokenErrorCode(_ rawCode: String?) -> String? {
        guard let rawCode else { return nil }
        let code = rawCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty, code.count <= 80 else { return nil }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-")
        guard code.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            return nil
        }
        return code
    }

    // MARK: - PKCE helpers

    private static func randomURLSafeString(count: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }

    private static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncodedString()
    }

    private static func urlEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
