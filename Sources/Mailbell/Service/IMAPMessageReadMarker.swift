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
        // Grouped by mailbox *and* generation: two identities that share a
        // mailbox name but not a generation are not the same target.
        let identitiesByTarget = Dictionary(grouping: identities) { identity in
            ReadTarget(mailboxName: identity.mailboxName, uidValidity: identity.uidValidity)
        }
        guard !identitiesByTarget.isEmpty else { return }

        let accessToken = try await AccountTokenProvider(
            accountID: account.id,
            providerID: account.providerID,
            config: config
        ).validAccessToken()

        let client = IMAPClient()
        try await client.connect()
        defer { client.disconnect() }

        try await client.authenticate(email: account.email, accessToken: accessToken)
        var staleTargets: [ReadTarget] = []
        for target in identitiesByTarget.keys.sorted() {
            guard let uids = identitiesByTarget[target]?.map(\.uid) else { continue }
            try await client.selectMailbox(target.mailboxName)
            do {
                try await client.markAsRead(uids: uids, requiringUIDValidity: target.uidValidity)
            } catch let error as IMAPClient.IMAPError {
                guard case .staleMailboxGeneration = error else { throw error }
                // Recoverable: the rest of the account still gets marked, and
                // the caller is told so the local state is not advanced.
                staleTargets.append(target)
            }
        }

        guard staleTargets.isEmpty else {
            throw IMAPClient.IMAPError.staleMailboxGeneration(
                expected: staleTargets[0].uidValidity,
                actual: client.selectedUIDValidity ?? 0
            )
        }
    }

    struct ReadTarget: Hashable, Comparable {
        let mailboxName: String
        let uidValidity: Int

        static func < (lhs: Self, rhs: Self) -> Bool {
            (lhs.mailboxName, lhs.uidValidity) < (rhs.mailboxName, rhs.uidValidity)
        }
    }
}
