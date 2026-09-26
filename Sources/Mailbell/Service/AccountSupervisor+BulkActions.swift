import Foundation
import MailbellKit

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
                String(localized: "No messages awaiting review.")
            case .markedAllAsRead(let count):
                String(localized: "Marked \(MenuCopy.reviewCountText(count).lowercased()) as read in Gmail.")
            case .partiallyMarkedAsRead(let marked, let failed):
                String(localized: "Marked \(marked) as read. \(failed) could not be updated in Gmail.")
            case .markAsReadFailed:
                String(localized: "Couldn't mark messages as read in Gmail. Try again.")
            case .dismissedAll(let count):
                String(localized: "Dismissed \(MenuCopy.reviewCountText(count).lowercased()) from Mailbell.")
            }
        }
    }

    /// True when at least one retained group carries an IMAP UID, which is what
    /// the server-side `UID STORE` needs.
    var canMarkAllAsRead: Bool {
        reviewQueue.retainedConversations.contains(where: \.canMarkAsRead)
    }

    /// Marks every retained group as read on the server, including the ones
    /// beyond the visible rows, one authenticated IMAP session per account, then
    /// removes the groups locally. Publishes once.
    @discardableResult
    func markAllAsRead() async -> BulkActionResult {
        let groups = reviewQueue.retainedConversations
        guard !groups.isEmpty else { return .nothingPending }

        var marked = 0
        var failed = 0

        for account in accounts {
            let accountGroups = groups.filter { $0.accountID == account.id }
            guard !accountGroups.isEmpty else { continue }

            var identities: [IMAPMessageIdentity] = []
            var submissions: [ReadSubmission] = []
            for submission in reviewQueue.readSubmissions(containing: accountGroups.map(\.id)) {
                if submission.isEmpty {
                    failed += 1
                    continue
                }
                identities.append(contentsOf: submission.identities)
                submissions.append(submission)
            }
            guard !identities.isEmpty else { continue }

            do {
                let config = try configProvider()
                try await emailReadMarker(account, config, identities)
                try reviewQueue.markRead(submissions: submissions)
                marked += submissions.count
            } catch {
                failed += submissions.count
                applyMarkAsReadFailure(error, accountID: account.id)
            }
        }

        // Pending items whose account has since been removed cannot be marked.
        let knownAccountIDs = Set(accounts.map(\.id))
        let orphanCount = groups.filter { !knownAccountIDs.contains($0.accountID) }.count
        failed += orphanCount

        applyReviewQueueWarning(accountID: nil)
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
    func dismissAll() -> BulkActionResult {
        do {
            let count = try reviewQueue.dismissAll()
            guard count > 0 else { return .nothingPending }
            applyReviewQueueWarning(accountID: nil)
            publish()
            return .dismissedAll(count: count)
        } catch {
            handleHandledHistoryFailure(error, accountID: nil)
            return .nothingPending
        }
    }
}
