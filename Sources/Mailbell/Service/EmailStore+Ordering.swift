import Foundation

/// How the queue is grouped and ordered: one row per Gmail conversation, newest
/// server receipt first, and the first-admitted message as each conversation's
/// representative.
@MainActor
extension EmailStore {
    var items: [EmailStoreItem] {
        let chronology = groupChronology()
        let ordered = groupedItems().sorted { left, right in
            isNewerInQueue(left, than: right, chronology: chronology)
        }
        // A projection of the retained store, not a second queue: the rows are
        // capped per account, while every retained message stays actionable.
        var shownPerAccount: [UUID: Int] = [:]
        return ordered.filter { item in
            let shown = shownPerAccount[item.accountID, default: 0]
            guard shown < PendingQueueBudget.visibleConversationsPerAccount else { return false }
            shownPerAccount[item.accountID] = shown + 1
            return true
        }
    }

    func groupedItems() -> [EmailStoreItem] {
        var firstItemsByGroupID: [String: EmailStoreItem] = [:]
        for item in itemsByID.values {
            guard let existing = firstItemsByGroupID[item.groupID] else {
                firstItemsByGroupID[item.groupID] = item
                continue
            }
            if isEarlierInGroup(item, than: existing) {
                firstItemsByGroupID[item.groupID] = item
            }
        }
        return Array(firstItemsByGroupID.values)
    }

    func firstItem(groupID: String) -> EmailStoreItem? {
        itemsByID.values
            .filter { $0.groupID == groupID }
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
            latest[item.groupID] = Swift.max(latest[item.groupID] ?? receivedAt, receivedAt)
        }
    }

    func isNewerInQueue(
        _ left: EmailStoreItem,
        than right: EmailStoreItem,
        chronology: [String: Date]
    ) -> Bool {
        switch (chronology[left.groupID], chronology[right.groupID]) {
        case let (leftDate?, rightDate?) where leftDate != rightDate:
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
        return left.title.localizedCaseInsensitiveCompare(right.title) == .orderedAscending
    }

    func isEarlierInGroup(_ left: EmailStoreItem, than right: EmailStoreItem) -> Bool {
        if left.receivedAt != right.receivedAt {
            return left.receivedAt < right.receivedAt
        }
        if left.admissionOrder != right.admissionOrder {
            return left.admissionOrder < right.admissionOrder
        }
        if let leftUID = left.imapIdentity?.uid,
           let rightUID = right.imapIdentity?.uid,
           leftUID != rightUID {
            return leftUID < rightUID
        }
        return left.title.localizedCaseInsensitiveCompare(right.title) == .orderedAscending
    }
}
