import Foundation

// Nonisolated: refreshes tokens inside MailMonitor run tasks and the read-marker task.
nonisolated final class AccountTokenProvider {
    private let store: TokenStore
    private let oauth: OAuthClient

    init(accountID: UUID, providerID: MailProviderID, config: OAuthConfig) {
        store = TokenStore(accountID: accountID, providerID: providerID)
        oauth = OAuthClient(config: config)
    }

    var hasSession: Bool {
        store.hasSession
    }

    func hasStoredSession() throws -> Bool {
        try store.hasStoredSession()
    }

    func clear() {
        store.clear()
    }

    func validAccessToken() async throws -> String {
        guard let tokens = try store.loadTokens(), let refreshToken = tokens.refreshToken else {
            throw OAuthClient.OAuthError.noRefreshToken
        }
        if tokens.isAccessTokenValid, !tokens.accessToken.isEmpty {
            return tokens.accessToken
        }
        return try await refreshAccessToken(refreshToken: refreshToken)
    }

    func refreshAccessToken() async throws -> String {
        guard let tokens = try store.loadTokens(), let refreshToken = tokens.refreshToken else {
            throw OAuthClient.OAuthError.noRefreshToken
        }
        return try await refreshAccessToken(refreshToken: refreshToken)
    }

    private func refreshAccessToken(refreshToken: String) async throws -> String {
        let refreshed = try await oauth.refresh(refreshToken: refreshToken)
        do {
            try store.save(tokens: refreshed)
        } catch {
            Log.auth.error("Failed to save refreshed token: \(Log.detail(error), privacy: .private)")
            throw OAuthClient.OAuthError.refreshUnavailable("could not save the refreshed token")
        }
        return refreshed.accessToken
    }
}
