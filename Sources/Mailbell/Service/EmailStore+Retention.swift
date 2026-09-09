import Foundation

/// One retained message weighed for release when an account is over budget.
private struct EvictionCandidate {
    let id: String
    let isRepresentative: Bool
    let groupAge: TimeInterval
    let order: Int
}

@MainActor
extension EmailStore {
    /// Keeps one account inside its retained-message budget.
    ///
    /// Eviction releases reconstructible local context only. It never records a
    /// disposition and never touches Gmail, so an evicted message is not
    /// handled — it is simply outside the recent window, and Gmail still has
    /// it. Older conversations give up their extra context first, and a
    /// conversation loses its row only once its representative is all that is
    /// left of it.
    func enforceRetentionBudget(accountID: UUID) {
        let retained = itemsByID.values.filter { $0.accountID == accountID }
        var overflow = retained.count - PendingQueueBudget.retainedMessagesPerAccount
        guard overflow > 0 else { return }

        // Sort keys are precomputed rather than derived inside the comparator:
        // looking up a group's chronology per comparison hashes a string on
        // every one of them, which made an at-capacity admission cost 10ms.
        // Scoped to this account: another account's mail cannot influence how
        // this one is trimmed, and iterating it would only cost time.
        var chronology: [String: Date] = [:]
        var representatives: [String: EmailStoreItem] = [:]
        for item in retained {
            if let receivedAt = item.serverReceivedAt {
                chronology[item.groupID] = Swift.max(chronology[item.groupID] ?? receivedAt, receivedAt)
            }
            guard let existing = representatives[item.groupID] else {
                representatives[item.groupID] = item
                continue
            }
            if isEarlierInGroup(item, than: existing) {
                representatives[item.groupID] = item
            }
        }
        let representativeIDs = Set(representatives.values.map(\.id))
        let ranked = retained
            .map { item in
                EvictionCandidate(
                    id: item.id,
                    isRepresentative: representativeIDs.contains(item.id),
                    // Undated groups are the oldest thing we know of.
                    groupAge: chronology[item.groupID]?.timeIntervalSinceReferenceDate
                        ?? -.greatestFiniteMagnitude,
                    order: item.admissionOrder
                )
            }


        // Extra context before any representative; then the least recent
        // conversation; then its newest members first, so the oldest surviving
        // ones stay the readable ones.
        func evictsBefore(_ left: EvictionCandidate, _ right: EvictionCandidate) -> Bool {
            if left.isRepresentative != right.isRepresentative {
                return !left.isRepresentative
            }
            if left.groupAge != right.groupAge {
                return left.groupAge < right.groupAge
            }
            return left.order > right.order
        }

        // Steady state overflows by one message per new arrival, so picking the
        // single worst candidate beats ordering all five hundred of them.
        var evicted: Set<String> = []
        var remaining = ranked
        while overflow > 0, !remaining.isEmpty {
            guard let index = remaining.indices.min(by: { evictsBefore(remaining[$0], remaining[$1]) })
            else {
                break
            }
            evicted.insert(remaining[index].id)
            remaining.remove(at: index)
            overflow -= 1
        }

        guard !evicted.isEmpty else { return }
        itemsByID = itemsByID.filter { id, _ in !evicted.contains(id) }
    }
}
