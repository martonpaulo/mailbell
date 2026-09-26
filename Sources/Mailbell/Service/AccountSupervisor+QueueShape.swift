import Foundation

/// What the retained window holds versus what the menu can show. Kept honest
/// and separate: the queue is a recent window over Gmail, and the interface has
/// to be able to say so without inventing a total for the mail it cannot see.
extension AccountSupervisor {
    func hiddenConversationCount(accountID: UUID) -> Int {
        reviewQueue.hiddenConversationCount(accountID: accountID)
    }

    /// Conversations each account holds beyond its visible rows.
    var hiddenConversationCounts: [UUID: Int] {
        accounts.reduce(into: [:]) { counts, account in
            counts[account.id] = reviewQueue.hiddenConversationCount(accountID: account.id)
        }
    }
}
