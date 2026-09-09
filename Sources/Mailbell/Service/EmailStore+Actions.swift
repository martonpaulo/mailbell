import Foundation

/// What the user does to the queue: open, mark as read, dismiss, and their
/// whole-queue forms. Separated from the store itself, which is about what the
/// queue holds rather than how it is acted on.
@MainActor
extension EmailStore {
    func dismiss(id: String) throws {
        try removeGroup(containing: id, disposition: .dismissed)
    }

    func markOpened(id: String) throws {
        try removeGroup(containing: id, disposition: .opened)
    }

    /// Finalizes exactly the members the server was asked about. Anything that
    /// joined the thread during the round trip stays pending, because nothing
    /// marked it read.
    func markRead(submission: ReadSubmission) throws {
        try markRead(submissions: [submission])
    }

    /// One transition for a whole bulk run: a single history write and a single
    /// pass over the store, instead of re-encoding the handled history and
    /// rescanning the queue once per conversation.
    func markRead(submissions: [ReadSubmission]) throws {
        let submitted = Set(submissions.flatMap(\.itemIDs))
        guard !submitted.isEmpty else { return }

        let handled = submitted.map { id in
            itemsByID[id].map(handledMessage) ?? HandledMessage(id: id, identity: nil)
        }
        try persistence.mark(handled, disposition: .markedRead)
        itemsByID = itemsByID.filter { id, _ in !submitted.contains(id) }
    }

    /// Dismisses every pending item in one persistence write and returns how
    /// many groups (menu rows) were cleared.
    @discardableResult
    func dismissAll() throws -> Int {
        guard !itemsByID.isEmpty else { return 0 }
        let groupCount = Set(itemsByID.values.map(\.groupID)).count
        try persistence.mark(itemsByID.values.map(handledMessage), disposition: .dismissed)
        itemsByID = [:]
        return groupCount
    }

    func removeGroup(containing id: String, disposition: EmailStoreDisposition) throws {
        guard let item = itemsByID[id] else {
            try persistence.mark(HandledMessage(id: id, identity: nil), disposition: disposition)
            itemsByID[id] = nil
            return
        }

        let groupID = item.groupID
        let grouped = itemsByID.values
            .filter { $0.groupID == groupID }
            .map(handledMessage)
        try persistence.mark(grouped, disposition: disposition)
        itemsByID = itemsByID.filter { _, item in
            item.groupID != groupID
        }
    }

    func handledMessage(for item: EmailStoreItem) -> HandledMessage {
        HandledMessage(id: item.id, identity: item.imapIdentity)
    }
}
