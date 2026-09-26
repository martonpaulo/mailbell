import XCTest

@testable import MailbellKit

final class ReviewQueueTests: XCTestCase {
    @MainActor
    func testAdmitsUnreadEmailWhenNotHandled() throws {
        let store = ReviewQueueFixture.makeStore()
        let account = ReviewQueueFixture.makeAccount()
        let header = ReviewQueueFixture.makeHeader(gmMessageId: "1001")

        XCTAssertTrue(try store.admit(header: header, account: account))

        XCTAssertEqual(store.shownItems.count, 1)
        XCTAssertEqual(store.shownItems.first?.subject, "Subject")
        XCTAssertEqual(store.shownItems.first?.sender, "Sender <sender@example.com>")
        XCTAssertNil(store.shownItems.first?.bodyPreview)
        XCTAssertEqual(
            store.shownItems.first?.imapIdentity,
            IMAPMessageIdentity(uid: 1, mailboxName: "INBOX", uidValidity: 1)
        )
        XCTAssertTrue(store.shownItems.first?.canMarkAsRead == true)
    }

    @MainActor
    func testDismissedEmailIsExcludedAfterRelaunch() throws {
        let defaults = ReviewQueueFixture.makeDefaults()
        let account = ReviewQueueFixture.makeAccount()
        let header = ReviewQueueFixture.makeHeader(gmMessageId: "1002")
        let id = ReviewItemIdentity.id(accountID: account.id, header: header)

        let store = ReviewQueueFixture.makeStore(defaults: defaults)
        XCTAssertTrue(try store.admit(header: header, account: account))
        try store.dismiss(id: id)

        let relaunchedStore = ReviewQueueFixture.makeStore(defaults: defaults)
        XCTAssertFalse(try relaunchedStore.admit(header: header, account: account))
        XCTAssertTrue(relaunchedStore.shownItems.isEmpty)
    }

    @MainActor
    func testOpenedEmailIsExcludedAfterRelaunch() throws {
        let defaults = ReviewQueueFixture.makeDefaults()
        let account = ReviewQueueFixture.makeAccount()
        let header = ReviewQueueFixture.makeHeader(gmMessageId: "1003")
        let id = ReviewItemIdentity.id(accountID: account.id, header: header)

        let store = ReviewQueueFixture.makeStore(defaults: defaults)
        XCTAssertTrue(try store.admit(header: header, account: account))
        try store.markOpened(id: id)

        let relaunchedStore = ReviewQueueFixture.makeStore(defaults: defaults)
        XCTAssertFalse(try relaunchedStore.admit(header: header, account: account))
        XCTAssertTrue(relaunchedStore.shownItems.isEmpty)
    }

    @MainActor
    func testMarkedReadEmailIsExcludedAfterRelaunch() throws {
        let defaults = ReviewQueueFixture.makeDefaults()
        let account = ReviewQueueFixture.makeAccount()
        let header = ReviewQueueFixture.makeHeader(gmMessageId: "1005")
        let id = ReviewItemIdentity.id(accountID: account.id, header: header)

        let store = ReviewQueueFixture.makeStore(defaults: defaults)
        XCTAssertTrue(try store.admit(header: header, account: account))
        try store.markRead(submission: store.readSubmission(containing: id))

        let relaunchedStore = ReviewQueueFixture.makeStore(defaults: defaults)
        XCTAssertFalse(try relaunchedStore.admit(header: header, account: account))
        XCTAssertTrue(relaunchedStore.shownItems.isEmpty)
    }

    @MainActor
    func testUnreadSyncAfterRelaunchExcludesDismissedAndRestoresProviderUnreadEmails() throws {
        let defaults = ReviewQueueFixture.makeDefaults()
        let account = ReviewQueueFixture.makeAccount()
        let dismissedHeader = ReviewQueueFixture.makeHeader(uid: 1, gmMessageId: "dismissed")
        let openedHeader = ReviewQueueFixture.makeHeader(uid: 2, subject: "Opened", gmMessageId: "opened")
        let markedReadHeader = ReviewQueueFixture.makeHeader(uid: 3, subject: "Marked Read", gmMessageId: "marked-read")
        let unreadHeader = ReviewQueueFixture.makeHeader(uid: 4, subject: "Unread", gmMessageId: "unread")

        let store = ReviewQueueFixture.makeStore(defaults: defaults)
        try store.dismiss(id: ReviewItemIdentity.id(accountID: account.id, header: dismissedHeader))
        try store.markOpened(id: ReviewItemIdentity.id(accountID: account.id, header: openedHeader))
        try store.markRead(
            submission: store.readSubmission(
                containing: ReviewItemIdentity.id(accountID: account.id, header: markedReadHeader)
            )
        )

        let relaunchedStore = ReviewQueueFixture.makeStore(defaults: defaults)
        let didChange = try relaunchedStore.reconcileUnread(
            snapshots: [ReviewQueueFixture.makeSnapshot(uids: [1, 2, 3, 4])],
            fetchedHeaders: [dismissedHeader, openedHeader, markedReadHeader, unreadHeader],
            account: account
        )

        XCTAssertTrue(didChange)
        XCTAssertEqual(Set(relaunchedStore.shownItems.map(\.subject)), Set(["Opened", "Marked Read", "Unread"]))
    }

    @MainActor
    func testUnreadSyncReplacesAccountItemsWithCurrentUnreadHeaders() throws {
        let store = ReviewQueueFixture.makeStore()
        let account = ReviewQueueFixture.makeAccount()
        let firstHeader = ReviewQueueFixture.makeHeader(
            uid: 1, subject: "Read elsewhere", gmMessageId: "read-elsewhere")
        let secondHeader = ReviewQueueFixture.makeHeader(uid: 2, subject: "Still unread", gmMessageId: "still-unread")

        XCTAssertTrue(
            try store.reconcileUnread(
                snapshots: [ReviewQueueFixture.makeSnapshot(uids: [1, 2])],
                fetchedHeaders: [firstHeader, secondHeader],
                account: account
            )
        )
        XCTAssertEqual(store.shownItems.map(\.subject), ["Read elsewhere", "Still unread"])

        XCTAssertTrue(
            try store.reconcileUnread(
                snapshots: [ReviewQueueFixture.makeSnapshot(uids: [2])],
                fetchedHeaders: [],
                account: account
            )
        )
        XCTAssertEqual(store.shownItems.map(\.subject), ["Still unread"])
    }

    @MainActor
    func testUnreadSyncRemovesExternallyReadMessageInsideThreadGroup() throws {
        let store = ReviewQueueFixture.makeStore()
        let account = ReviewQueueFixture.makeAccount()
        let firstHeader = ReviewQueueFixture.makeHeader(
            uid: 1,
            subject: "Read elsewhere",
            gmMessageId: "message-1",
            gmThreadId: "thread-1"
        )
        let secondHeader = ReviewQueueFixture.makeHeader(
            uid: 2,
            subject: "Still unread",
            gmMessageId: "message-2",
            gmThreadId: "thread-1"
        )

        XCTAssertTrue(try store.admit(header: firstHeader, account: account))
        XCTAssertTrue(try store.admit(header: secondHeader, account: account))

        XCTAssertTrue(
            try store.reconcileUnread(
                snapshots: [ReviewQueueFixture.makeSnapshot(uids: [2])],
                fetchedHeaders: [],
                account: account
            )
        )

        XCTAssertEqual(store.shownItems.map(\.subject), ["Still unread"])
        XCTAssertEqual(store.pendingUIDs(accountID: account.id, mailbox: .inbox, uidValidity: 1), Set([2]))
    }

    @MainActor
    func testUnreadSyncIsIdempotentForSameProviderState() throws {
        let store = ReviewQueueFixture.makeStore()
        let account = ReviewQueueFixture.makeAccount()
        let header = ReviewQueueFixture.makeHeader(uid: 1, subject: "Still unread", gmMessageId: "still-unread")

        XCTAssertTrue(
            try store.reconcileUnread(
                snapshots: [ReviewQueueFixture.makeSnapshot(uids: [1])],
                fetchedHeaders: [header],
                account: account
            )
        )
        XCTAssertFalse(
            try store.reconcileUnread(
                snapshots: [ReviewQueueFixture.makeSnapshot(uids: [1])],
                fetchedHeaders: [],
                account: account
            )
        )
        XCTAssertEqual(store.shownItems.map(\.subject), ["Still unread"])
    }

    @MainActor
    func testUnreadSyncUpdatesExistingItemFromCurrentProviderHeader() throws {
        let store = ReviewQueueFixture.makeStore()
        let account = ReviewQueueFixture.makeAccount()
        let inboxHeader = ReviewQueueFixture.makeHeader(uid: 1, subject: "Inbox", gmMessageId: "same-message")
        let spamHeader = ReviewQueueFixture.makeHeader(
            uid: 42,
            mailbox: .spam,
            mailboxName: "[Gmail]/Spam",
            subject: "Moved to spam",
            gmMessageId: "same-message"
        )

        XCTAssertTrue(
            try store.reconcileUnread(
                snapshots: [ReviewQueueFixture.makeSnapshot(uids: [1])],
                fetchedHeaders: [inboxHeader],
                account: account
            )
        )
        let original = try XCTUnwrap(store.shownItems.first)

        XCTAssertTrue(
            try store.reconcileUnread(
                snapshots: [
                    ReviewQueueFixture.makeSnapshot(uids: []),
                    ReviewQueueFixture.makeSnapshot(mailbox: .spam, mailboxName: "[Gmail]/Spam", uids: [42]),
                ],
                fetchedHeaders: [spamHeader],
                account: account
            )
        )

        let updated = try XCTUnwrap(store.shownItems.first)
        XCTAssertEqual(updated.id, original.id)
        XCTAssertEqual(updated.admittedAt, original.admittedAt)
        XCTAssertEqual(updated.subject, "(SPAM) Moved to spam")
        XCTAssertEqual(updated.mailbox, .spam)
        XCTAssertEqual(updated.imapIdentity, IMAPMessageIdentity(uid: 42, mailboxName: "[Gmail]/Spam", uidValidity: 1))
    }

    @MainActor
    func testDuplicateEmailsAreDeduplicatedByStableID() throws {
        let store = ReviewQueueFixture.makeStore()
        let account = ReviewQueueFixture.makeAccount()

        let firstHeader = ReviewQueueFixture.makeHeader(uid: 1, subject: "First", gmMessageId: "same")
        let duplicateHeader = ReviewQueueFixture.makeHeader(uid: 2, subject: "Second", gmMessageId: "same")

        XCTAssertTrue(try store.admit(header: firstHeader, account: account))
        XCTAssertFalse(try store.admit(header: duplicateHeader, account: account))

        XCTAssertEqual(store.shownItems.count, 1)
        XCTAssertEqual(store.shownItems.first?.subject, "First")
    }

    @MainActor
    func testThreadGroupExposesOnlyFirstPendingEmailButKeepsAllUIDs() throws {
        let store = ReviewQueueFixture.makeStore()
        let account = ReviewQueueFixture.makeAccount()

        let firstHeader = ReviewQueueFixture.makeHeader(
            uid: 1,
            subject: "First",
            gmMessageId: "message-1",
            gmThreadId: "thread-1",
            bodyPreview: "First preview"
        )
        let secondHeader = ReviewQueueFixture.makeHeader(
            uid: 2,
            subject: "Second",
            gmMessageId: "message-2",
            gmThreadId: "thread-1",
            bodyPreview: "Second preview"
        )

        XCTAssertTrue(try store.admit(header: firstHeader, account: account))
        XCTAssertTrue(try store.admit(header: secondHeader, account: account))

        let item = try XCTUnwrap(store.shownItems.first)
        XCTAssertEqual(store.shownItems.count, 1)
        XCTAssertEqual(item.subject, "First")
        XCTAssertEqual(item.bodyPreview, "First preview")
        XCTAssertEqual(item.bodyPreviewLines, ["First preview"])
        XCTAssertEqual(
            store.pendingUIDs(accountID: account.id, mailbox: .inbox, uidValidity: 1),
            Set([1, 2])
        )
        XCTAssertEqual(store.shownConversationCounts[account.id], 1)
    }

    @MainActor
    func testThreadGroupUsesFirstAdmittedEmailWhenUIDsTieOnReceivedAt() throws {
        let store = ReviewQueueFixture.makeStore()
        let account = ReviewQueueFixture.makeAccount()
        let firstAdmittedHeader = ReviewQueueFixture.makeHeader(
            uid: 2,
            subject: "First notified",
            gmMessageId: "message-2",
            gmThreadId: "thread-1",
            bodyPreview: "First notified preview"
        )
        let laterAdmittedHeader = ReviewQueueFixture.makeHeader(
            uid: 1,
            subject: "Earlier thread UID",
            gmMessageId: "message-1",
            gmThreadId: "thread-1",
            bodyPreview: "Earlier thread UID preview"
        )

        XCTAssertTrue(try store.admit(header: firstAdmittedHeader, account: account))
        XCTAssertTrue(try store.admit(header: laterAdmittedHeader, account: account))

        let item = try XCTUnwrap(store.shownItems.first)
        XCTAssertEqual(store.shownItems.count, 1)
        XCTAssertEqual(item.subject, "First notified")
        XCTAssertEqual(item.bodyPreview, "First notified preview")

        let laterAdmittedID = ReviewItemIdentity.id(accountID: account.id, header: laterAdmittedHeader)
        let firstItem = try XCTUnwrap(store.firstItemInGroup(containing: laterAdmittedID))
        XCTAssertEqual(firstItem.subject, "First notified")
    }

    @MainActor
    func testOpeningThreadGroupRemovesCurrentMessagesButAllowsFutureThreadMessages() throws {
        let defaults = ReviewQueueFixture.makeDefaults()
        let store = ReviewQueueFixture.makeStore(defaults: defaults)
        let account = ReviewQueueFixture.makeAccount()
        let firstHeader = ReviewQueueFixture.makeHeader(uid: 1, gmMessageId: "message-1", gmThreadId: "thread-1")
        let secondHeader = ReviewQueueFixture.makeHeader(uid: 2, gmMessageId: "message-2", gmThreadId: "thread-1")
        let futureHeader = ReviewQueueFixture.makeHeader(uid: 3, gmMessageId: "message-3", gmThreadId: "thread-1")

        XCTAssertTrue(try store.admit(header: firstHeader, account: account))
        XCTAssertTrue(try store.admit(header: secondHeader, account: account))
        try store.markOpened(id: ReviewItemIdentity.id(accountID: account.id, header: firstHeader))

        XCTAssertTrue(store.shownItems.isEmpty)
        XCTAssertFalse(try store.admit(header: secondHeader, account: account))
        XCTAssertTrue(try store.admit(header: futureHeader, account: account))
        XCTAssertEqual(store.shownItems.map(\.subject), ["Subject"])
    }

    @MainActor
    func testFirstItemInGroupResolvesNotificationForLaterThreadMessage() throws {
        let store = ReviewQueueFixture.makeStore()
        let account = ReviewQueueFixture.makeAccount()
        let firstHeader = ReviewQueueFixture.makeHeader(
            uid: 1,
            subject: "First",
            gmMessageId: "message-1",
            gmThreadId: "thread-1"
        )
        let secondHeader = ReviewQueueFixture.makeHeader(
            uid: 2,
            subject: "Second",
            gmMessageId: "message-2",
            gmThreadId: "thread-1"
        )

        XCTAssertTrue(try store.admit(header: firstHeader, account: account))
        XCTAssertTrue(try store.admit(header: secondHeader, account: account))

        let secondID = ReviewItemIdentity.id(accountID: account.id, header: secondHeader)
        let firstItem = try XCTUnwrap(store.firstItemInGroup(containing: secondID))
        XCTAssertEqual(firstItem.subject, "First")
    }
}
