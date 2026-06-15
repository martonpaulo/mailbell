import Foundation

final class AccountTokenProvider {
    private let store: TokenStore
    private let oauth: OAuthClient

    init(accountID: UUID, providerID: MailProviderID, config: OAuthConfig) {
        store = TokenStore(accountID: accountID, providerID: providerID)
        oauth = OAuthClient(config: config)
    }

    var hasSession: Bool {
        store.hasSession
    }

    func clear() {
        store.clear()
    }

    func validAccessToken() async throws -> String {
        guard let tokens = store.loadTokens(), let refreshToken = tokens.refreshToken else {
            throw OAuthClient.OAuthError.noRefreshToken
        }
        if tokens.isAccessTokenValid, !tokens.accessToken.isEmpty {
            return tokens.accessToken
        }
        let refreshed = try await oauth.refresh(refreshToken: refreshToken)
        do {
            try store.save(tokens: refreshed)
        } catch {
            Log.error("Failed to save refreshed token: \(error.localizedDescription)")
            throw OAuthClient.OAuthError.refreshUnavailable("Could not save refreshed token.")
        }
        return refreshed.accessToken
    }
}
