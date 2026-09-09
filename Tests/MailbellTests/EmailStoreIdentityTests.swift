@testable import mailbell
import XCTest

/// What makes two messages the same message, and what keeps a UID from being
/// mistaken for an identity across mailboxes and accounts.
final class EmailStoreIdentityTests: XCTestCase {
    func testStableIdentityPrefersProviderIDsOverSubject() {
        let account = EmailStoreFixture.makeAccount()
        let first = EmailStoreFixture.makeHeader(uid: 1, subject: "First", gmMessageId: "provider-id")
        let second = EmailStoreFixture.makeHeader(uid: 2, subject: "Second", gmMessageId: "provider-id")

        XCTAssertEqual(
            EmailStoreIdentity.id(accountID: account.id, header: first),
            EmailStoreIdentity.id(accountID: account.id, header: second)
        )
    }

    func testStableIdentitySeparatesUIDFallbackByMailbox() {
        let account = EmailStoreFixture.makeAccount()
        let inbox = EmailStoreFixture.makeHeader(uid: 1, mailbox: .inbox)
        let spam = EmailStoreFixture.makeHeader(uid: 1, mailbox: .spam)

        XCTAssertNotEqual(
            EmailStoreIdentity.id(accountID: account.id, header: inbox),
            EmailStoreIdentity.id(accountID: account.id, header: spam)
        )
    }

    @MainActor
    func testPendingItemKeepsUIDAndSelectedMailboxNameTogether() throws {
        let store = EmailStoreFixture.makeStore()
        let account = EmailStoreFixture.makeAccount()
        let header = EmailStoreFixture.makeHeader(
            uid: 42,
            mailbox: .spam,
            mailboxName: "[Gmail]/Spam",
            gmMessageId: "spam-uid"
        )

        XCTAssertTrue(try store.admit(header: header, account: account))

        let item = try XCTUnwrap(store.items.first)
        XCTAssertEqual(item.mailbox, .spam)
        XCTAssertEqual(item.imapIdentity, IMAPMessageIdentity(uid: 42, mailboxName: "[Gmail]/Spam", uidValidity: 1))
        XCTAssertTrue(item.canMarkAsRead)
    }

    @MainActor
    func testPendingUIDsAreScopedByAccountAndMailbox() throws {
        let store = EmailStoreFixture.makeStore()
        let account = EmailStoreFixture.makeAccount()
        let otherAccount = MailAccount(providerID: .gmail, email: "other@example.com")

        XCTAssertTrue(try store.admit(
            header: EmailStoreFixture.makeHeader(uid: 1, gmMessageId: "inbox"),
            account: account
        ))
        XCTAssertTrue(
            try store.admit(
                header: EmailStoreFixture.makeHeader(
                    uid: 2,
                    mailbox: .spam,
                    mailboxName: "[Gmail]/Spam",
                    gmMessageId: "spam"
                ),
                account: account
            )
        )
        XCTAssertTrue(try store.admit(
            header: EmailStoreFixture.makeHeader(uid: 3, gmMessageId: "other"),
            account: otherAccount
        ))

        XCTAssertEqual(store.pendingUIDs(accountID: account.id, mailbox: .inbox, uidValidity: 1), Set([1]))
        XCTAssertEqual(store.pendingUIDs(accountID: account.id, mailbox: .spam, uidValidity: 1), Set([2]))
    }

    @MainActor
    func testPendingItemWithoutPositiveUIDCannotBeMarkedAsRead() throws {
        let store = EmailStoreFixture.makeStore()
        let account = EmailStoreFixture.makeAccount()
        let header = EmailStoreFixture.makeHeader(uid: 0, gmMessageId: "legacy")

        XCTAssertTrue(try store.admit(header: header, account: account))

        let item = try XCTUnwrap(store.items.first)
        XCTAssertNil(item.imapIdentity)
        XCTAssertFalse(item.canMarkAsRead)
    }

    @MainActor
    func testRemoveSpamItemsKeepsInboxItems() throws {
        let store = EmailStoreFixture.makeStore()
        let account = EmailStoreFixture.makeAccount()

        XCTAssertTrue(try store.admit(
            header: EmailStoreFixture.makeHeader(subject: "Inbox", gmMessageId: "inbox"),
            account: account
        ))
        XCTAssertTrue(
            try store.admit(
                header: EmailStoreFixture.makeHeader(mailbox: .spam, subject: "Spam", gmMessageId: "spam"),
                account: account
            )
        )

        XCTAssertTrue(store.removeSpamItems())

        XCTAssertEqual(store.items.map(\.title), ["Inbox"])
        XCTAssertFalse(store.removeSpamItems())
    }

    @MainActor
    func testDismissAndOpenAreIdempotent() throws {
        let defaults = EmailStoreFixture.makeDefaults()
        let account = EmailStoreFixture.makeAccount()
        let header = EmailStoreFixture.makeHeader(gmMessageId: "1004")
        let id = EmailStoreIdentity.id(accountID: account.id, header: header)
        let store = EmailStoreFixture.makeStore(defaults: defaults)

        XCTAssertTrue(try store.admit(header: header, account: account))
        try store.dismiss(id: id)
        try store.dismiss(id: id)
        try store.markOpened(id: id)
        try store.markOpened(id: id)
        try store.markRead(submission: store.readSubmission(containing: id))
        try store.markRead(submission: store.readSubmission(containing: id))

        XCTAssertTrue(store.items.isEmpty)

        let relaunchedStore = EmailStoreFixture.makeStore(defaults: defaults)
        XCTAssertFalse(try relaunchedStore.admit(header: header, account: account))
    }
}
