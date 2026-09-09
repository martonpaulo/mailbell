import Foundation

/// Exchanging an authorization code, refreshing, and reading back the signed-in
/// address. Separate from the interactive sign-in that produces the code, and
/// from the PKCE material that protects it.
extension OAuthClient {
    func exchangeCode(_ code: String, verifier: String, redirectURI: String) async throws -> GoogleTokens {
        let form = tokenForm([
            "client_id": config.clientID,
            "code": code,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "redirect_uri": redirectURI
        ])

        do {
            let response: TokenResponse = try await postForm(config.tokenEndpoint, form: form)
            return response.tokens(existingRefreshToken: nil)
        } catch {
            throw OAuthError.tokenExchangeFailed(error.localizedDescription)
        }
    }

    /// Exchanges a refresh token for a fresh access token.
    func refresh(refreshToken: String) async throws -> GoogleTokens {
        let form = tokenForm([
            "client_id": config.clientID,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ])

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

    func fetchEmail(accessToken: String) async throws -> String {
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

    func postForm<T: Decodable>(_ url: URL, form: [String: String]) async throws -> T {
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

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = resourceTimeout
        return URLSession(configuration: configuration)
    }

    func tokenForm(_ fields: [String: String]) -> [String: String] {
        var form = fields
        if let clientSecret = config.clientSecret?.trimmingCharacters(in: .whitespacesAndNewlines),
           !clientSecret.isEmpty {
            form["client_secret"] = clientSecret
        }
        return form
    }

    static func oauthError(from error: Error) -> Error {
        guard let loopbackError = error as? LoopbackServer.LoopbackError else {
            return error
        }
        switch loopbackError {
        case let .providerError(detail):
            return OAuthError.authorizationDenied(detail)
        case .missingCode:
            return OAuthError.missingCode
        case .missingState, .stateMismatch:
            return OAuthError.authorizationDenied("state mismatch")
        case .failedToStart, .timedOut, .cancelled:
            return loopbackError
        }
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
}
