import Foundation

/// OAuth token material returned by Google's token endpoint.
struct GoogleTokens: Codable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date

    var isAccessTokenValid: Bool {
        // Treat tokens within 60s of expiry as expired to avoid mid-request failures.
        expiresAt.timeIntervalSinceNow > 60
    }
}

/// Raw shape of Google's token endpoint response.
struct TokenResponse: Decodable {
    let accessToken: String
    let expiresIn: Int
    let refreshToken: String?
    let tokenType: String
    let scope: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
        case scope
    }

    func tokens(existingRefreshToken: String?) -> GoogleTokens {
        GoogleTokens(
            accessToken: accessToken,
            refreshToken: refreshToken ?? existingRefreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(expiresIn))
        )
    }
}
