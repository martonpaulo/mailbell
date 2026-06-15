import Foundation

enum IMAPMessageReadMarker {
    static func markAsRead(
        account: MailAccount,
        config: OAuthConfig,
        identity: IMAPMessageIdentity
    ) async throws {
        let accessToken = try await AccountTokenProvider(
            accountID: account.id,
            providerID: account.providerID,
            config: config
        ).validAccessToken()

        let client = IMAPClient()
        try await client.connect()
        defer { client.disconnect() }

        try await client.authenticate(email: account.email, accessToken: accessToken)
        try await client.selectMailbox(identity.mailboxName)
        try await client.markAsRead(uid: identity.uid)
    }
}
