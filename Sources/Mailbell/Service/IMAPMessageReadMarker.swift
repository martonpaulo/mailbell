import Foundation

enum IMAPMessageReadMarker {
    /// Marks every identity as read over a single authenticated IMAP session,
    /// selecting each mailbox once. Bulk actions must never open one connection
    /// per message.
    static func markAsRead(
        account: MailAccount,
        config: OAuthConfig,
        identities: [IMAPMessageIdentity]
    ) async throws {
        let uidsByMailbox = Dictionary(grouping: identities, by: \.mailboxName)
            .mapValues { $0.map(\.uid) }
        guard !uidsByMailbox.isEmpty else { return }

        let accessToken = try await AccountTokenProvider(
            accountID: account.id,
            providerID: account.providerID,
            config: config
        ).validAccessToken()

        let client = IMAPClient()
        try await client.connect()
        defer { client.disconnect() }

        try await client.authenticate(email: account.email, accessToken: accessToken)
        for mailboxName in uidsByMailbox.keys.sorted() {
            guard let uids = uidsByMailbox[mailboxName] else { continue }
            try await client.selectMailbox(mailboxName)
            try await client.markAsRead(uids: uids)
        }
    }
}
