@testable import mailbell
import XCTest

/// Reconciliation fetches a bounded window of the newest unknown unread UIDs.
/// When that whole window is already dismissed, re-selecting it on every cycle
/// spends the entire budget on messages that are discarded on arrival, and
/// older unread mail never enters the queue.
final class EmailStoreReconciliationProgressTests: XCTestCase {
    private let mailboxName = "INBOX"
    private let generation = 1

    @MainActor
    func testDismissedMessagesAreSkippedSoOlderMailGetsATurn() throws {
        let defaults = makeDefaults()
        let account = makeAccount()
        let store = makeStore(defaults: defaults)

        // The newest window is admitted and then dismissed.
        for uid in 101 ... 200 {
            XCTAssertTrue(try store.admit(header: makeHeader(uid: uid), account: account))
        }
        XCTAssertEqual(try store.dismissAll(), 100)

        // Relaunch: pending items are gone, the dismissals are not.
        let relaunched = makeStore(defaults: defaults)

        // The defect, made visible: the old skip set was pending items alone,
        // which after a relaunch is empty — so the same dismissed window was
        // selected again on every cycle.
        XCTAssertTrue(
            relaunched.pendingUIDs(accountID: account.id, mailbox: .inbox, uidValidity: generation).isEmpty
        )

        let skipped = try relaunched.uidsToSkip(
            accountID: account.id,
            mailbox: .inbox,
            mailboxName: mailboxName,
            uidValidity: generation
        )

        XCTAssertEqual(skipped, Set(101 ... 200))
        // Which is what leaves room for the older half.
        let unread = Set(1 ... 200)
        XCTAssertEqual(unread.subtracting(skipped), Set(1 ... 100))
    }

    @MainActor
    func testPendingAndHandledUIDsAreBothSkipped() throws {
        let defaults = makeDefaults()
        let account = makeAccount()
        let store = makeStore(defaults: defaults)

        XCTAssertTrue(try store.admit(header: makeHeader(uid: 10), account: account))
        XCTAssertTrue(try store.admit(header: makeHeader(uid: 20), account: account))
        try store.dismiss(id: EmailStoreIdentity.id(accountID: account.id, header: makeHeader(uid: 20)))

        let skipped = try store.uidsToSkip(
            accountID: account.id,
            mailbox: .inbox,
            mailboxName: mailboxName,
            uidValidity: generation
        )

        XCTAssertEqual(skipped, [10, 20])
    }

    @MainActor
    func testHistoryWithoutALocationIsBackfilledOnTheCycleThatMeetsIt() throws {
        let defaults = makeDefaults()
        let account = makeAccount()
        let store = makeStore(defaults: defaults)

        // A record written before Mailbell stored locations: dismissed while the
        // item was not pending, so no identity was available.
        let header = makeHeader(uid: 150)
        try store.dismiss(id: EmailStoreIdentity.id(accountID: account.id, header: header))
        XCTAssertTrue(
            try store.uidsToSkip(
                accountID: account.id,
                mailbox: .inbox,
                mailboxName: mailboxName,
                uidValidity: generation
            ).isEmpty,
            "a record with no location cannot be skipped yet"
        )

        // The cycle that downloads it teaches the record where it lives.
        _ = try store.reconcileUnread(
            snapshots: [makeSnapshot(unreadUIDs: [150])],
            fetchedHeaders: [header],
            account: account
        )

        XCTAssertEqual(
            try store.uidsToSkip(
                accountID: account.id,
                mailbox: .inbox,
                mailboxName: mailboxName,
                uidValidity: generation
            ),
            [150],
            "the next cycle must not download it again"
        )
    }

    @MainActor
    func testASuppressedMessageStaysSuppressedAfterBackfill() throws {
        let account = makeAccount()
        let store = makeStore(defaults: makeDefaults())
        let header = makeHeader(uid: 150)
        try store.dismiss(id: EmailStoreIdentity.id(accountID: account.id, header: header))

        _ = try store.reconcileUnread(
            snapshots: [makeSnapshot(unreadUIDs: [150])],
            fetchedHeaders: [header],
            account: account
        )

        XCTAssertTrue(store.items.isEmpty, "backfilling a location must not re-admit the message")
        XCTAssertFalse(try store.admit(header: header, account: account))
    }

    @MainActor
    func testSkippingIsScopedToTheMailboxGenerationAndAccount() throws {
        let account = makeAccount()
        let store = makeStore(defaults: makeDefaults())
        XCTAssertTrue(try store.admit(header: makeHeader(uid: 42), account: account))
        try store.dismiss(id: EmailStoreIdentity.id(accountID: account.id, header: makeHeader(uid: 42)))

        XCTAssertEqual(
            try store.uidsToSkip(
                accountID: account.id,
                mailbox: .inbox,
                mailboxName: mailboxName,
                uidValidity: generation
            ),
            [42]
        )
        // A rebuilt mailbox reuses numbers, so its UID 42 is a different message.
        XCTAssertTrue(try store.uidsToSkip(
            accountID: account.id,
            mailbox: .inbox,
            mailboxName: mailboxName,
            uidValidity: 2
        ).isEmpty)
        // So is the same number in another mailbox, or another account.
        XCTAssertTrue(try store.uidsToSkip(
            accountID: account.id,
            mailbox: .spam,
            mailboxName: "[Gmail]/Spam",
            uidValidity: generation
        ).isEmpty)
        XCTAssertTrue(try store.uidsToSkip(
            accountID: UUID(),
            mailbox: .inbox,
            mailboxName: mailboxName,
            uidValidity: generation
        ).isEmpty)
    }

    @MainActor
    func testRemovingAnAccountForgetsWhatItAskedToSkip() throws {
        let account = makeAccount()
        let store = makeStore(defaults: makeDefaults())
        XCTAssertTrue(try store.admit(header: makeHeader(uid: 42), account: account))
        try store.dismiss(id: EmailStoreIdentity.id(accountID: account.id, header: makeHeader(uid: 42)))

        try store.removeAccountRecords(accountID: account.id)

        XCTAssertTrue(try store.uidsToSkip(
            accountID: account.id,
            mailbox: .inbox,
            mailboxName: mailboxName,
            uidValidity: generation
        ).isEmpty)
    }

    // MARK: - Helpers

    private func makeDefaults() -> UserDefaults {
        let suiteName = "mailbell.tests.progress.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @MainActor
    private func makeStore(defaults: UserDefaults) -> EmailStore {
        EmailStore(persistence: EmailStorePersistence(userDefaults: defaults))
    }

    private func makeAccount() -> MailAccount {
        MailAccount(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            providerID: .gmail,
            email: "account@example.com"
        )
    }

    private func makeSnapshot(unreadUIDs: Set<Int>) -> MailboxUnreadSnapshot {
        MailboxUnreadSnapshot(
            mailbox: .inbox,
            mailboxName: mailboxName,
            uidValidity: generation,
            unreadUIDs: unreadUIDs
        )
    }

    private func makeHeader(uid: Int) -> MessageHeader {
        MessageHeader(
            uid: uid,
            mailboxName: mailboxName,
            from: "sender@example.com",
            subject: "Subject \(uid)",
            date: "",
            gmThreadId: nil,
            gmMessageId: "msg-\(uid)",
            uidValidity: generation
        )
    }
}
