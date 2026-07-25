import Foundation

extension AccountSupervisor {
    /// Outcome of a bulk action over every item awaiting review. Bulk work is
    /// best effort: one account failing must not strand the rest.
    enum BulkActionResult: Equatable {
        case nothingPending
        case markedAllAsRead(count: Int)
        case partiallyMarkedAsRead(marked: Int, failed: Int)
        case markAsReadFailed
        case dismissedAll(count: Int)

        var message: String {
            switch self {
            case .nothingPending:
                "No messages awaiting review."
            case let .markedAllAsRead(count):
                "Marked \(PendingCopy.reviewCountText(count).lowercased()) as read in Gmail."
            case let .partiallyMarkedAsRead(marked, failed):
                "Marked \(marked) as read. \(failed) could not be updated in Gmail."
            case .markAsReadFailed:
                "Could not mark messages as read in Gmail."
            case let .dismissedAll(count):
                "Dismissed \(PendingCopy.reviewCountText(count).lowercased()) from Mailbell."
            }
        }
    }

    /// True when at least one pending group carries an IMAP UID, which is what
    /// the server-side `UID STORE` needs.
    var canMarkAllAsRead: Bool {
        emailStoreItems.contains(where: \.canMarkAsRead)
    }

    /// Marks every pending group as read on the server, one authenticated IMAP
    /// session per account, then removes the groups locally. Publishes once.
    @discardableResult
    func markAllEmailsAsRead() async -> BulkActionResult {
        let groups = emailStoreItems
        guard !groups.isEmpty else { return .nothingPending }

        var marked = 0
        var failed = 0

        for account in accounts {
            let accountGroups = groups.filter { $0.accountID == account.id }
            guard !accountGroups.isEmpty else { continue }

            var identities: [IMAPMessageIdentity] = []
            var markableGroupIDs: [String] = []
            for group in accountGroups {
                let groupIdentities = emailStore.imapIdentitiesInGroup(containing: group.id)
                if groupIdentities.isEmpty {
                    failed += 1
                    continue
                }
                identities.append(contentsOf: groupIdentities)
                markableGroupIDs.append(group.id)
            }
            guard !identities.isEmpty else { continue }

            do {
                let config = try configProvider()
                try await emailReadMarker(account, config, identities)
                for id in markableGroupIDs {
                    try emailStore.markRead(id: id)
                }
                marked += markableGroupIDs.count
            } catch {
                failed += markableGroupIDs.count
                applyMarkAsReadFailure(error, accountID: account.id)
            }
        }

        // Pending items whose account has since been removed cannot be marked.
        let knownAccountIDs = Set(accounts.map(\.id))
        let orphanCount = groups.filter { !knownAccountIDs.contains($0.accountID) }.count
        failed += orphanCount

        applyEmailStoreWarning(accountID: nil)
        publish()

        if marked == 0 {
            return failed > 0 ? .markAsReadFailed : .nothingPending
        }
        return failed > 0
            ? .partiallyMarkedAsRead(marked: marked, failed: failed)
            : .markedAllAsRead(count: marked)
    }

    /// Clears every pending item locally. Gmail is not touched: dismissed items
    /// stay unread in the mailbox and are suppressed from unread reconciliation.
    @discardableResult
    func dismissAllEmails() -> BulkActionResult {
        do {
            let count = try emailStore.dismissAll()
            guard count > 0 else { return .nothingPending }
            applyEmailStoreWarning(accountID: nil)
            publish()
            return .dismissedAll(count: count)
        } catch {
            handleEmailStorePersistenceFailure(error, accountID: nil)
            return .nothingPending
        }
    }
}
