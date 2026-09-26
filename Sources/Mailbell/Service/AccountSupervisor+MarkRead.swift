import Foundation
import MailbellKit

extension AccountSupervisor {
    /// Returns whether Gmail marked the conversation as read, so the caller
    /// can report a failure the menu is no longer open to show.
    @discardableResult
    func markAsRead(itemID id: String) async -> Bool {
        guard let item = reviewQueue.item(id: id) else { return false }
        let submission = reviewQueue.readSubmission(containing: id)
        guard !submission.isEmpty else {
            Log.monitor.error("Cannot mark email as read because the pending item has no IMAP UID.")
            return false
        }
        guard let account = accounts.first(where: { $0.id == item.accountID }) else {
            Log.monitor.error("Cannot mark email as read because the account was not found.")
            return false
        }

        do {
            let config = try configProvider()
            try await emailReadMarker(account, config, submission.identities)
            try reviewQueue.markRead(submission: submission)
            applyReviewQueueWarning(accountID: account.id)
            publish()
            return true
        } catch {
            applyMarkAsReadFailure(error, accountID: account.id)
            publish()
            return false
        }
    }

    /// Records a mark-as-read failure without publishing, so a bulk run can
    /// collect every account's outcome and notify observers exactly once.
    func applyMarkAsReadFailure(_ error: Error, accountID: UUID) {
        Log.monitor.error("Failed to mark email as read: \(Log.detail(error), privacy: .private)")
        if error is HandledHistory.PersistenceError {
            applyHandledHistoryFailure(error, accountID: accountID)
            return
        }
        guard let oauthError = error as? OAuthClient.OAuthError else {
            connectionErrors[accountID] = error.localizedDescription
            return
        }

        switch oauthError {
        case .refreshFailed, .noRefreshToken:
            statuses[accountID] = .signInRequired
            connectionErrors[accountID] = oauthError.localizedDescription
        default:
            break
        }
    }
}
