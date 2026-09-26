import Foundation

/// How the queue is grouped and ordered: one row per Gmail conversation, newest
/// server receipt first, and the first-admitted message as each conversation's
/// representative.
@MainActor
extension ReviewQueue {
    public var shownItems: [ReviewItem] {
        let chronology = groupChronology()
        let ordered = groupedItems().sorted { left, right in
            isNewerInQueue(left, than: right, chronology: chronology)
        }
        // A projection of the retained store, not a second queue: the rows are
        // capped per account, while every retained message stays actionable.
        var shownPerAccount: [UUID: Int] = [:]
        return ordered.filter { item in
            let shown = shownPerAccount[item.accountID, default: 0]
            guard shown < ReviewQueueBudget.shownConversationsPerAccount else { return false }
            shownPerAccount[item.accountID] = shown + 1
            return true
        }
    }

    func groupedItems() -> [ReviewItem] {
        var firstItemsByConversationID: [String: ReviewItem] = [:]
        for item in itemsByID.values {
            guard let existing = firstItemsByConversationID[item.conversationID] else {
                firstItemsByConversationID[item.conversationID] = item
                continue
            }
            if isEarlierInGroup(item, than: existing) {
                firstItemsByConversationID[item.conversationID] = item
            }
        }
        return Array(firstItemsByConversationID.values)
    }

    func firstItem(conversationID: String) -> ReviewItem? {
        itemsByID.values
            .filter { $0.conversationID == conversationID }
            .min { left, right in
                isEarlierInGroup(left, than: right)
            }
    }

    /// A conversation is as new as its newest pending member, so a reply lifts
    /// the whole thread the way it does in Gmail. Members Mailbell no longer
    /// holds do not count, which is what makes removal recompute the order.
    func groupChronology() -> [String: Date] {
        itemsByID.values.reduce(into: [:]) { latest, item in
            guard let receivedAt = item.serverReceivedAt else { return }
            latest[item.conversationID] = Swift.max(latest[item.conversationID] ?? receivedAt, receivedAt)
        }
    }

    func isNewerInQueue(
        _ left: ReviewItem,
        than right: ReviewItem,
        chronology: [String: Date]
    ) -> Bool {
        switch (chronology[left.conversationID], chronology[right.conversationID]) {
        case (let leftDate?, let rightDate?) where leftDate != rightDate:
            return leftDate > rightDate
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        default:
            break
        }
        // Undated groups, and exact ties, fall back to the order Mailbell saw
        // them so the queue never reshuffles on its own.
        if left.admissionOrder != right.admissionOrder {
            return left.admissionOrder < right.admissionOrder
        }
        return left.subject.localizedCaseInsensitiveCompare(right.subject) == .orderedAscending
    }

    func isEarlierInGroup(_ left: ReviewItem, than right: ReviewItem) -> Bool {
        if left.admittedAt != right.admittedAt {
            return left.admittedAt < right.admittedAt
        }
        if left.admissionOrder != right.admissionOrder {
            return left.admissionOrder < right.admissionOrder
        }
        if let leftUID = left.imapIdentity?.uid,
            let rightUID = right.imapIdentity?.uid,
            leftUID != rightUID
        {
            return leftUID < rightUID
        }
        return left.subject.localizedCaseInsensitiveCompare(right.subject) == .orderedAscending
    }
}
