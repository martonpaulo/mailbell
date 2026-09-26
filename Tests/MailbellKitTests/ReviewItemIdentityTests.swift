@testable import MailbellKit
import XCTest

/// What makes two messages the same message, and what keeps a UID from being
/// mistaken for an identity across mailboxes and accounts.
final class ReviewItemIdentityTests: XCTestCase {
    func testStableIdentityPrefersProviderIDsOverSubject() {
        let account = ReviewQueueFixture.makeAccount()
        let first = ReviewQueueFixture.makeHeader(uid: 1, subject: "First", gmMessageId: "provider-id")
        let second = ReviewQueueFixture.makeHeader(uid: 2, subject: "Second", gmMessageId: "provider-id")

        XCTAssertEqual(
            ReviewItemIdentity.id(accountID: account.id, header: first),
            ReviewItemIdentity.id(accountID: account.id, header: second)
        )
    }

    func testStableIdentitySeparatesUIDFallbackByMailbox() {
        let account = ReviewQueueFixture.makeAccount()
        let inbox = ReviewQueueFixture.makeHeader(uid: 1, mailbox: .inbox)
        let spam = ReviewQueueFixture.makeHeader(uid: 1, mailbox: .spam)

        XCTAssertNotEqual(
            ReviewItemIdentity.id(accountID: account.id, header: inbox),
            ReviewItemIdentity.id(accountID: account.id, header: spam)
        )
    }

    @MainActor
    func testPendingItemKeepsUIDAndSelectedMailboxNameTogether() throws {
        let store = ReviewQueueFixture.makeStore()
        let account = ReviewQueueFixture.makeAccount()
        let header = ReviewQueueFixture.makeHeader(
            uid: 42,
            mailbox: .spam,
            mailboxName: "[Gmail]/Spam",
            gmMessageId: "spam-uid"
        )

        XCTAssertTrue(try store.admit(header: header, account: account))

        let item = try XCTUnwrap(store.shownItems.first)
        XCTAssertEqual(item.mailbox, .spam)
        XCTAssertEqual(item.imapIdentity, IMAPMessageIdentity(uid: 42, mailboxName: "[Gmail]/Spam", uidValidity: 1))
        XCTAssertTrue(item.canMarkAsRead)
    }

    @MainActor
    func testPendingUIDsAreScopedByAccountAndMailbox() throws {
        let store = ReviewQueueFixture.makeStore()
        let account = ReviewQueueFixture.makeAccount()
        let otherAccount = MailAccount(providerID: .gmail, email: "other@example.com")

        XCTAssertTrue(try store.admit(
            header: ReviewQueueFixture.makeHeader(uid: 1, gmMessageId: "inbox"),
            account: account
        ))
        XCTAssertTrue(
            try store.admit(
                header: ReviewQueueFixture.makeHeader(
                    uid: 2,
                    mailbox: .spam,
                    mailboxName: "[Gmail]/Spam",
                    gmMessageId: "spam"
                ),
                account: account
            )
        )
        XCTAssertTrue(try store.admit(
            header: ReviewQueueFixture.makeHeader(uid: 3, gmMessageId: "other"),
            account: otherAccount
        ))

        XCTAssertEqual(store.pendingUIDs(accountID: account.id, mailbox: .inbox, uidValidity: 1), Set([1]))
        XCTAssertEqual(store.pendingUIDs(accountID: account.id, mailbox: .spam, uidValidity: 1), Set([2]))
    }

    @MainActor
    func testPendingItemWithoutPositiveUIDCannotBeMarkedAsRead() throws {
        let store = ReviewQueueFixture.makeStore()
        let account = ReviewQueueFixture.makeAccount()
        let header = ReviewQueueFixture.makeHeader(uid: 0, gmMessageId: "legacy")

        XCTAssertTrue(try store.admit(header: header, account: account))

        let item = try XCTUnwrap(store.shownItems.first)
        XCTAssertNil(item.imapIdentity)
        XCTAssertFalse(item.canMarkAsRead)
    }

    @MainActor
    func testRemoveSpamItemsKeepsInboxItems() throws {
        let store = ReviewQueueFixture.makeStore()
        let account = ReviewQueueFixture.makeAccount()

        XCTAssertTrue(try store.admit(
            header: ReviewQueueFixture.makeHeader(subject: "Inbox", gmMessageId: "inbox"),
            account: account
        ))
        XCTAssertTrue(
            try store.admit(
                header: ReviewQueueFixture.makeHeader(mailbox: .spam, subject: "Spam", gmMessageId: "spam"),
                account: account
            )
        )

        XCTAssertTrue(store.removeSpamItems())

        XCTAssertEqual(store.shownItems.map(\.subject), ["Inbox"])
        XCTAssertFalse(store.removeSpamItems())
    }

    @MainActor
    func testDismissAndOpenAreIdempotent() throws {
        let defaults = ReviewQueueFixture.makeDefaults()
        let account = ReviewQueueFixture.makeAccount()
        let header = ReviewQueueFixture.makeHeader(gmMessageId: "1004")
        let id = ReviewItemIdentity.id(accountID: account.id, header: header)
        let store = ReviewQueueFixture.makeStore(defaults: defaults)

        XCTAssertTrue(try store.admit(header: header, account: account))
        try store.dismiss(id: id)
        try store.dismiss(id: id)
        try store.markOpened(id: id)
        try store.markOpened(id: id)
        try store.markRead(submission: store.readSubmission(containing: id))
        try store.markRead(submission: store.readSubmission(containing: id))

        XCTAssertTrue(store.shownItems.isEmpty)

        let relaunchedStore = ReviewQueueFixture.makeStore(defaults: defaults)
        XCTAssertFalse(try relaunchedStore.admit(header: header, account: account))
    }
}
