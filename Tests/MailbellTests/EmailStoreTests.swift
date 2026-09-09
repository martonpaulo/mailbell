@testable import mailbell
import XCTest

// swiftlint:disable:next type_body_length
final class EmailStoreTests: XCTestCase {
    @MainActor
    func testAdmitsUnreadEmailWhenNotHandled() throws {
        let store = EmailStoreFixture.makeStore()
        let account = EmailStoreFixture.makeAccount()
        let header = EmailStoreFixture.makeHeader(gmMessageId: "1001")

        XCTAssertTrue(try store.admit(header: header, account: account))

        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.items.first?.title, "Subject")
        XCTAssertEqual(store.items.first?.sender, "Sender <sender@example.com>")
        XCTAssertNil(store.items.first?.bodyPreview)
        XCTAssertEqual(
            store.items.first?.imapIdentity,
            IMAPMessageIdentity(uid: 1, mailboxName: "INBOX", uidValidity: 1)
        )
        XCTAssertTrue(store.items.first?.canMarkAsRead == true)
    }

    @MainActor
    func testDismissedEmailIsExcludedAfterRelaunch() throws {
        let defaults = EmailStoreFixture.makeDefaults()
        let account = EmailStoreFixture.makeAccount()
        let header = EmailStoreFixture.makeHeader(gmMessageId: "1002")
        let id = EmailStoreIdentity.id(accountID: account.id, header: header)

        let store = EmailStoreFixture.makeStore(defaults: defaults)
        XCTAssertTrue(try store.admit(header: header, account: account))
        try store.dismiss(id: id)

        let relaunchedStore = EmailStoreFixture.makeStore(defaults: defaults)
        XCTAssertFalse(try relaunchedStore.admit(header: header, account: account))
        XCTAssertTrue(relaunchedStore.items.isEmpty)
    }

    @MainActor
    func testOpenedEmailIsExcludedAfterRelaunch() throws {
        let defaults = EmailStoreFixture.makeDefaults()
        let account = EmailStoreFixture.makeAccount()
        let header = EmailStoreFixture.makeHeader(gmMessageId: "1003")
        let id = EmailStoreIdentity.id(accountID: account.id, header: header)

        let store = EmailStoreFixture.makeStore(defaults: defaults)
        XCTAssertTrue(try store.admit(header: header, account: account))
        try store.markOpened(id: id)

        let relaunchedStore = EmailStoreFixture.makeStore(defaults: defaults)
        XCTAssertFalse(try relaunchedStore.admit(header: header, account: account))
        XCTAssertTrue(relaunchedStore.items.isEmpty)
    }

    @MainActor
    func testMarkedReadEmailIsExcludedAfterRelaunch() throws {
        let defaults = EmailStoreFixture.makeDefaults()
        let account = EmailStoreFixture.makeAccount()
        let header = EmailStoreFixture.makeHeader(gmMessageId: "1005")
        let id = EmailStoreIdentity.id(accountID: account.id, header: header)

        let store = EmailStoreFixture.makeStore(defaults: defaults)
        XCTAssertTrue(try store.admit(header: header, account: account))
        try store.markRead(submission: store.readSubmission(containing: id))

        let relaunchedStore = EmailStoreFixture.makeStore(defaults: defaults)
        XCTAssertFalse(try relaunchedStore.admit(header: header, account: account))
        XCTAssertTrue(relaunchedStore.items.isEmpty)
    }

    @MainActor
    func testUnreadSyncAfterRelaunchExcludesDismissedAndRestoresProviderUnreadEmails() throws {
        let defaults = EmailStoreFixture.makeDefaults()
        let account = EmailStoreFixture.makeAccount()
        let dismissedHeader = EmailStoreFixture.makeHeader(uid: 1, gmMessageId: "dismissed")
        let openedHeader = EmailStoreFixture.makeHeader(uid: 2, subject: "Opened", gmMessageId: "opened")
        let markedReadHeader = EmailStoreFixture.makeHeader(uid: 3, subject: "Marked Read", gmMessageId: "marked-read")
        let unreadHeader = EmailStoreFixture.makeHeader(uid: 4, subject: "Unread", gmMessageId: "unread")

        let store = EmailStoreFixture.makeStore(defaults: defaults)
        try store.dismiss(id: EmailStoreIdentity.id(accountID: account.id, header: dismissedHeader))
        try store.markOpened(id: EmailStoreIdentity.id(accountID: account.id, header: openedHeader))
        try store.markRead(
            submission: store.readSubmission(
                containing: EmailStoreIdentity.id(accountID: account.id, header: markedReadHeader)
            )
        )

        let relaunchedStore = EmailStoreFixture.makeStore(defaults: defaults)
        let didChange = try relaunchedStore.reconcileUnread(
            snapshots: [EmailStoreFixture.makeSnapshot(uids: [1, 2, 3, 4])],
            fetchedHeaders: [dismissedHeader, openedHeader, markedReadHeader, unreadHeader],
            account: account
        )

        XCTAssertTrue(didChange)
        XCTAssertEqual(Set(relaunchedStore.items.map(\.title)), Set(["Opened", "Marked Read", "Unread"]))
    }

    @MainActor
    func testUnreadSyncReplacesAccountItemsWithCurrentUnreadHeaders() throws {
        let store = EmailStoreFixture.makeStore()
        let account = EmailStoreFixture.makeAccount()
        let firstHeader = EmailStoreFixture.makeHeader(uid: 1, subject: "Read elsewhere", gmMessageId: "read-elsewhere")
        let secondHeader = EmailStoreFixture.makeHeader(uid: 2, subject: "Still unread", gmMessageId: "still-unread")

        XCTAssertTrue(
            try store.reconcileUnread(
                snapshots: [EmailStoreFixture.makeSnapshot(uids: [1, 2])],
                fetchedHeaders: [firstHeader, secondHeader],
                account: account
            )
        )
        XCTAssertEqual(store.items.map(\.title), ["Read elsewhere", "Still unread"])

        XCTAssertTrue(
            try store.reconcileUnread(
                snapshots: [EmailStoreFixture.makeSnapshot(uids: [2])],
                fetchedHeaders: [],
                account: account
            )
        )
        XCTAssertEqual(store.items.map(\.title), ["Still unread"])
    }

    @MainActor
    func testUnreadSyncRemovesExternallyReadMessageInsideThreadGroup() throws {
        let store = EmailStoreFixture.makeStore()
        let account = EmailStoreFixture.makeAccount()
        let firstHeader = EmailStoreFixture.makeHeader(
            uid: 1,
            subject: "Read elsewhere",
            gmMessageId: "message-1",
            gmThreadId: "thread-1"
        )
        let secondHeader = EmailStoreFixture.makeHeader(
            uid: 2,
            subject: "Still unread",
            gmMessageId: "message-2",
            gmThreadId: "thread-1"
        )

        XCTAssertTrue(try store.admit(header: firstHeader, account: account))
        XCTAssertTrue(try store.admit(header: secondHeader, account: account))

        XCTAssertTrue(
            try store.reconcileUnread(
                snapshots: [EmailStoreFixture.makeSnapshot(uids: [2])],
                fetchedHeaders: [],
                account: account
            )
        )

        XCTAssertEqual(store.items.map(\.title), ["Still unread"])
        XCTAssertEqual(store.pendingUIDs(accountID: account.id, mailbox: .inbox, uidValidity: 1), Set([2]))
    }

    @MainActor
    func testUnreadSyncIsIdempotentForSameProviderState() throws {
        let store = EmailStoreFixture.makeStore()
        let account = EmailStoreFixture.makeAccount()
        let header = EmailStoreFixture.makeHeader(uid: 1, subject: "Still unread", gmMessageId: "still-unread")

        XCTAssertTrue(
            try store.reconcileUnread(
                snapshots: [EmailStoreFixture.makeSnapshot(uids: [1])],
                fetchedHeaders: [header],
                account: account
            )
        )
        XCTAssertFalse(
            try store.reconcileUnread(
                snapshots: [EmailStoreFixture.makeSnapshot(uids: [1])],
                fetchedHeaders: [],
                account: account
            )
        )
        XCTAssertEqual(store.items.map(\.title), ["Still unread"])
    }

    @MainActor
    func testUnreadSyncUpdatesExistingItemFromCurrentProviderHeader() throws {
        let store = EmailStoreFixture.makeStore()
        let account = EmailStoreFixture.makeAccount()
        let inboxHeader = EmailStoreFixture.makeHeader(uid: 1, subject: "Inbox", gmMessageId: "same-message")
        let spamHeader = EmailStoreFixture.makeHeader(
            uid: 42,
            mailbox: .spam,
            mailboxName: "[Gmail]/Spam",
            subject: "Moved to spam",
            gmMessageId: "same-message"
        )

        XCTAssertTrue(
            try store.reconcileUnread(
                snapshots: [EmailStoreFixture.makeSnapshot(uids: [1])],
                fetchedHeaders: [inboxHeader],
                account: account
            )
        )
        let original = try XCTUnwrap(store.items.first)

        XCTAssertTrue(
            try store.reconcileUnread(
                snapshots: [
                    EmailStoreFixture.makeSnapshot(uids: []),
                    EmailStoreFixture.makeSnapshot(mailbox: .spam, mailboxName: "[Gmail]/Spam", uids: [42])
                ],
                fetchedHeaders: [spamHeader],
                account: account
            )
        )

        let updated = try XCTUnwrap(store.items.first)
        XCTAssertEqual(updated.id, original.id)
        XCTAssertEqual(updated.receivedAt, original.receivedAt)
        XCTAssertEqual(updated.title, "(SPAM) Moved to spam")
        XCTAssertEqual(updated.mailbox, .spam)
        XCTAssertEqual(updated.imapIdentity, IMAPMessageIdentity(uid: 42, mailboxName: "[Gmail]/Spam", uidValidity: 1))
    }

    @MainActor
    func testDuplicateEmailsAreDeduplicatedByStableID() throws {
        let store = EmailStoreFixture.makeStore()
        let account = EmailStoreFixture.makeAccount()

        let firstHeader = EmailStoreFixture.makeHeader(uid: 1, subject: "First", gmMessageId: "same")
        let duplicateHeader = EmailStoreFixture.makeHeader(uid: 2, subject: "Second", gmMessageId: "same")

        XCTAssertTrue(try store.admit(header: firstHeader, account: account))
        XCTAssertFalse(try store.admit(header: duplicateHeader, account: account))

        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.items.first?.title, "First")
    }

    @MainActor
    func testThreadGroupExposesOnlyFirstPendingEmailButKeepsAllUIDs() throws {
        let store = EmailStoreFixture.makeStore()
        let account = EmailStoreFixture.makeAccount()

        let firstHeader = EmailStoreFixture.makeHeader(
            uid: 1,
            subject: "First",
            gmMessageId: "message-1",
            gmThreadId: "thread-1",
            bodyPreview: "First preview"
        )
        let secondHeader = EmailStoreFixture.makeHeader(
            uid: 2,
            subject: "Second",
            gmMessageId: "message-2",
            gmThreadId: "thread-1",
            bodyPreview: "Second preview"
        )

        XCTAssertTrue(try store.admit(header: firstHeader, account: account))
        XCTAssertTrue(try store.admit(header: secondHeader, account: account))

        let item = try XCTUnwrap(store.items.first)
        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(item.title, "First")
        XCTAssertEqual(item.bodyPreview, "First preview")
        XCTAssertEqual(item.bodyPreviewLines, ["First preview"])
        XCTAssertEqual(
            store.pendingUIDs(accountID: account.id, mailbox: .inbox, uidValidity: 1),
            Set([1, 2])
        )
        XCTAssertEqual(store.pendingCountsByAccountID[account.id], 1)
    }

    @MainActor
    func testThreadGroupUsesFirstAdmittedEmailWhenUIDsTieOnReceivedAt() throws {
        let store = EmailStoreFixture.makeStore()
        let account = EmailStoreFixture.makeAccount()
        let firstAdmittedHeader = EmailStoreFixture.makeHeader(
            uid: 2,
            subject: "First notified",
            gmMessageId: "message-2",
            gmThreadId: "thread-1",
            bodyPreview: "First notified preview"
        )
        let laterAdmittedHeader = EmailStoreFixture.makeHeader(
            uid: 1,
            subject: "Earlier thread UID",
            gmMessageId: "message-1",
            gmThreadId: "thread-1",
            bodyPreview: "Earlier thread UID preview"
        )

        XCTAssertTrue(try store.admit(header: firstAdmittedHeader, account: account))
        XCTAssertTrue(try store.admit(header: laterAdmittedHeader, account: account))

        let item = try XCTUnwrap(store.items.first)
        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(item.title, "First notified")
        XCTAssertEqual(item.bodyPreview, "First notified preview")

        let laterAdmittedID = EmailStoreIdentity.id(accountID: account.id, header: laterAdmittedHeader)
        let firstItem = try XCTUnwrap(store.firstItemInGroup(containing: laterAdmittedID))
        XCTAssertEqual(firstItem.title, "First notified")
    }

    @MainActor
    func testOpeningThreadGroupRemovesCurrentMessagesButAllowsFutureThreadMessages() throws {
        let defaults = EmailStoreFixture.makeDefaults()
        let store = EmailStoreFixture.makeStore(defaults: defaults)
        let account = EmailStoreFixture.makeAccount()
        let firstHeader = EmailStoreFixture.makeHeader(uid: 1, gmMessageId: "message-1", gmThreadId: "thread-1")
        let secondHeader = EmailStoreFixture.makeHeader(uid: 2, gmMessageId: "message-2", gmThreadId: "thread-1")
        let futureHeader = EmailStoreFixture.makeHeader(uid: 3, gmMessageId: "message-3", gmThreadId: "thread-1")

        XCTAssertTrue(try store.admit(header: firstHeader, account: account))
        XCTAssertTrue(try store.admit(header: secondHeader, account: account))
        try store.markOpened(id: EmailStoreIdentity.id(accountID: account.id, header: firstHeader))

        XCTAssertTrue(store.items.isEmpty)
        XCTAssertFalse(try store.admit(header: secondHeader, account: account))
        XCTAssertTrue(try store.admit(header: futureHeader, account: account))
        XCTAssertEqual(store.items.map(\.title), ["Subject"])
    }

    @MainActor
    func testFirstItemInGroupResolvesNotificationForLaterThreadMessage() throws {
        let store = EmailStoreFixture.makeStore()
        let account = EmailStoreFixture.makeAccount()
        let firstHeader = EmailStoreFixture.makeHeader(
            uid: 1,
            subject: "First",
            gmMessageId: "message-1",
            gmThreadId: "thread-1"
        )
        let secondHeader = EmailStoreFixture.makeHeader(
            uid: 2,
            subject: "Second",
            gmMessageId: "message-2",
            gmThreadId: "thread-1"
        )

        XCTAssertTrue(try store.admit(header: firstHeader, account: account))
        XCTAssertTrue(try store.admit(header: secondHeader, account: account))

        let secondID = EmailStoreIdentity.id(accountID: account.id, header: secondHeader)
        let firstItem = try XCTUnwrap(store.firstItemInGroup(containing: secondID))
        XCTAssertEqual(firstItem.title, "First")
    }
}
