import Foundation

/// What the retained window holds versus what the menu can show. Kept honest
/// and separate: the queue is a recent window over Gmail, and the interface has
/// to be able to say so without inventing a total for the mail it cannot see.
extension AccountSupervisor {
    func hiddenConversationCount(accountID: UUID) -> Int {
        emailStore.hiddenConversationCount(accountID: accountID)
    }

    var retainedMessageCount: Int {
        accountStates.reduce(0) { $0 + emailStore.retainedMessageCount(accountID: $1.account.id) }
    }
}
