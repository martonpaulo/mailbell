@testable import mailbell
import XCTest

final class EmailStoreTests: XCTestCase {
    @MainActor
    func testAdmitsUnreadEmailWhenNotHandled() {
        let store = makeStore()
        let account = makeAccount()
        let header = makeHeader(gmMessageId: "1001")

        XCTAssertTrue(store.admit(header: header, account: account))

        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.items.first?.title, "Subject")
        XCTAssertEqual(store.items.first?.sender, "Sender <sender@example.com>")
        XCTAssertNil(store.items.first?.bodyPreview)
        XCTAssertEqual(store.items.first?.imapIdentity, IMAPMessageIdentity(uid: 1, mailboxName: "INBOX"))
        XCTAssertTrue(store.items.first?.canMarkAsRead == true)
    }

    @MainActor
    func testDismissedEmailIsExcludedAfterRelaunch() {
        let defaults = makeDefaults()
        let account = makeAccount()
        let header = makeHeader(gmMessageId: "1002")
        let id = EmailStoreIdentity.id(accountID: account.id, header: header)

        let store = makeStore(defaults: defaults)
        XCTAssertTrue(store.admit(header: header, account: account))
        store.dismiss(id: id)

        let relaunchedStore = makeStore(defaults: defaults)
        XCTAssertFalse(relaunchedStore.admit(header: header, account: account))
        XCTAssertTrue(relaunchedStore.items.isEmpty)
    }

    @MainActor
    func testOpenedEmailIsExcludedAfterRelaunch() {
        let defaults = makeDefaults()
        let account = makeAccount()
        let header = makeHeader(gmMessageId: "1003")
        let id = EmailStoreIdentity.id(accountID: account.id, header: header)

        let store = makeStore(defaults: defaults)
        XCTAssertTrue(store.admit(header: header, account: account))
        store.markOpened(id: id)

        let relaunchedStore = makeStore(defaults: defaults)
        XCTAssertFalse(relaunchedStore.admit(header: header, account: account))
        XCTAssertTrue(relaunchedStore.items.isEmpty)
    }

    @MainActor
    func testMarkedReadEmailIsExcludedAfterRelaunch() {
        let defaults = makeDefaults()
        let account = makeAccount()
        let header = makeHeader(gmMessageId: "1005")
        let id = EmailStoreIdentity.id(accountID: account.id, header: header)

        let store = makeStore(defaults: defaults)
        XCTAssertTrue(store.admit(header: header, account: account))
        store.markRead(id: id)

        let relaunchedStore = makeStore(defaults: defaults)
        XCTAssertFalse(relaunchedStore.admit(header: header, account: account))
        XCTAssertTrue(relaunchedStore.items.isEmpty)
    }

    @MainActor
    func testUnreadSyncAfterRelaunchExcludesDismissedAndRestoresProviderUnreadEmails() {
        let defaults = makeDefaults()
        let account = makeAccount()
        let dismissedHeader = makeHeader(uid: 1, gmMessageId: "dismissed")
        let openedHeader = makeHeader(uid: 2, subject: "Opened", gmMessageId: "opened")
        let markedReadHeader = makeHeader(uid: 3, subject: "Marked Read", gmMessageId: "marked-read")
        let unreadHeader = makeHeader(uid: 4, subject: "Unread", gmMessageId: "unread")

        let store = makeStore(defaults: defaults)
        store.dismiss(id: EmailStoreIdentity.id(accountID: account.id, header: dismissedHeader))
        store.markOpened(id: EmailStoreIdentity.id(accountID: account.id, header: openedHeader))
        store.markRead(id: EmailStoreIdentity.id(accountID: account.id, header: markedReadHeader))

        let relaunchedStore = makeStore(defaults: defaults)
        let didChange = relaunchedStore.reconcileUnread(
            snapshots: [makeSnapshot(uids: [1, 2, 3, 4])],
            fetchedHeaders: [dismissedHeader, openedHeader, markedReadHeader, unreadHeader],
            account: account
        )

        XCTAssertTrue(didChange)
        XCTAssertEqual(Set(relaunchedStore.items.map(\.title)), Set(["Opened", "Marked Read", "Unread"]))
    }

    @MainActor
    func testUnreadSyncReplacesAccountItemsWithCurrentUnreadHeaders() {
        let store = makeStore()
        let account = makeAccount()
        let firstHeader = makeHeader(uid: 1, subject: "Read elsewhere", gmMessageId: "read-elsewhere")
        let secondHeader = makeHeader(uid: 2, subject: "Still unread", gmMessageId: "still-unread")

        XCTAssertTrue(
            store.reconcileUnread(
                snapshots: [makeSnapshot(uids: [1, 2])],
                fetchedHeaders: [firstHeader, secondHeader],
                account: account
            )
        )
        XCTAssertEqual(store.items.map(\.title), ["Read elsewhere", "Still unread"])

        XCTAssertTrue(
            store.reconcileUnread(
                snapshots: [makeSnapshot(uids: [2])],
                fetchedHeaders: [],
                account: account
            )
        )
        XCTAssertEqual(store.items.map(\.title), ["Still unread"])
    }

    @MainActor
    func testUnreadSyncRemovesExternallyReadMessageInsideThreadGroup() {
        let store = makeStore()
        let account = makeAccount()
        let firstHeader = makeHeader(uid: 1, subject: "Read elsewhere", gmMessageId: "message-1", gmThreadId: "thread-1")
        let secondHeader = makeHeader(uid: 2, subject: "Still unread", gmMessageId: "message-2", gmThreadId: "thread-1")

        XCTAssertTrue(store.admit(header: firstHeader, account: account))
        XCTAssertTrue(store.admit(header: secondHeader, account: account))

        XCTAssertTrue(
            store.reconcileUnread(
                snapshots: [makeSnapshot(uids: [2])],
                fetchedHeaders: [],
                account: account
            )
        )

        XCTAssertEqual(store.items.map(\.title), ["Still unread"])
        XCTAssertEqual(store.pendingUIDs(accountID: account.id, mailbox: .inbox), Set([2]))
    }

    @MainActor
    func testUnreadSyncIsIdempotentForSameProviderState() {
        let store = makeStore()
        let account = makeAccount()
        let header = makeHeader(uid: 1, subject: "Still unread", gmMessageId: "still-unread")

        XCTAssertTrue(
            store.reconcileUnread(
                snapshots: [makeSnapshot(uids: [1])],
                fetchedHeaders: [header],
                account: account
            )
        )
        XCTAssertFalse(
            store.reconcileUnread(
                snapshots: [makeSnapshot(uids: [1])],
                fetchedHeaders: [],
                account: account
            )
        )
        XCTAssertEqual(store.items.map(\.title), ["Still unread"])
    }

    @MainActor
    func testUnreadSyncUpdatesExistingItemFromCurrentProviderHeader() throws {
        let store = makeStore()
        let account = makeAccount()
        let inboxHeader = makeHeader(uid: 1, subject: "Inbox", gmMessageId: "same-message")
        let spamHeader = makeHeader(
            uid: 42,
            mailbox: .spam,
            mailboxName: "[Gmail]/Spam",
            subject: "Moved to spam",
            gmMessageId: "same-message"
        )

        XCTAssertTrue(
            store.reconcileUnread(
                snapshots: [makeSnapshot(uids: [1])],
                fetchedHeaders: [inboxHeader],
                account: account
            )
        )
        let original = try XCTUnwrap(store.items.first)

        XCTAssertTrue(
            store.reconcileUnread(
                snapshots: [
                    makeSnapshot(uids: []),
                    makeSnapshot(mailbox: .spam, mailboxName: "[Gmail]/Spam", uids: [42])
                ],
                fetchedHeaders: [spamHeader],
                account: account
            )
        )

        let updated = try XCTUnwrap(store.items.first)
        XCTAssertEqual(updated.id, original.id)
        XCTAssertEqual(updated.receivedAt, original.receivedAt)
        XCTAssertEqual(updated.title, "Moved to spam")
        XCTAssertEqual(updated.mailbox, .spam)
        XCTAssertEqual(updated.imapIdentity, IMAPMessageIdentity(uid: 42, mailboxName: "[Gmail]/Spam"))
    }

    @MainActor
    func testDuplicateEmailsAreDeduplicatedByStableID() {
        let store = makeStore()
        let account = makeAccount()

        let firstHeader = makeHeader(uid: 1, subject: "First", gmMessageId: "same")
        let duplicateHeader = makeHeader(uid: 2, subject: "Second", gmMessageId: "same")

        XCTAssertTrue(store.admit(header: firstHeader, account: account))
        XCTAssertFalse(store.admit(header: duplicateHeader, account: account))

        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.items.first?.title, "First")
    }

    @MainActor
    func testThreadGroupExposesOnlyFirstPendingEmailButKeepsAllUIDs() throws {
        let store = makeStore()
        let account = makeAccount()

        let firstHeader = makeHeader(
            uid: 1,
            subject: "First",
            gmMessageId: "message-1",
            gmThreadId: "thread-1",
            bodyPreview: "First preview"
        )
        let secondHeader = makeHeader(
            uid: 2,
            subject: "Second",
            gmMessageId: "message-2",
            gmThreadId: "thread-1",
            bodyPreview: "Second preview"
        )

        XCTAssertTrue(store.admit(header: firstHeader, account: account))
        XCTAssertTrue(store.admit(header: secondHeader, account: account))

        let item = try XCTUnwrap(store.items.first)
        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(item.title, "First")
        XCTAssertEqual(item.bodyPreview, "First preview")
        XCTAssertEqual(
            store.pendingUIDs(accountID: account.id, mailbox: .inbox),
            Set([1, 2])
        )
    }

    @MainActor
    func testOpeningThreadGroupRemovesCurrentMessagesButAllowsFutureThreadMessages() {
        let defaults = makeDefaults()
        let store = makeStore(defaults: defaults)
        let account = makeAccount()
        let firstHeader = makeHeader(uid: 1, gmMessageId: "message-1", gmThreadId: "thread-1")
        let secondHeader = makeHeader(uid: 2, gmMessageId: "message-2", gmThreadId: "thread-1")
        let futureHeader = makeHeader(uid: 3, gmMessageId: "message-3", gmThreadId: "thread-1")

        XCTAssertTrue(store.admit(header: firstHeader, account: account))
        XCTAssertTrue(store.admit(header: secondHeader, account: account))
        store.markOpened(id: EmailStoreIdentity.id(accountID: account.id, header: firstHeader))

        XCTAssertTrue(store.items.isEmpty)
        XCTAssertFalse(store.admit(header: secondHeader, account: account))
        XCTAssertTrue(store.admit(header: futureHeader, account: account))
        XCTAssertEqual(store.items.map(\.title), ["Subject"])
    }

    @MainActor
    func testFirstItemInGroupResolvesNotificationForLaterThreadMessage() throws {
        let store = makeStore()
        let account = makeAccount()
        let firstHeader = makeHeader(uid: 1, subject: "First", gmMessageId: "message-1", gmThreadId: "thread-1")
        let secondHeader = makeHeader(uid: 2, subject: "Second", gmMessageId: "message-2", gmThreadId: "thread-1")

        XCTAssertTrue(store.admit(header: firstHeader, account: account))
        XCTAssertTrue(store.admit(header: secondHeader, account: account))

        let secondID = EmailStoreIdentity.id(accountID: account.id, header: secondHeader)
        let firstItem = try XCTUnwrap(store.firstItemInGroup(containing: secondID))
        XCTAssertEqual(firstItem.title, "First")
    }

    func testStableIdentityPrefersProviderIDsOverSubject() {
        let account = makeAccount()
        let first = makeHeader(uid: 1, subject: "First", gmMessageId: "provider-id")
        let second = makeHeader(uid: 2, subject: "Second", gmMessageId: "provider-id")

        XCTAssertEqual(
            EmailStoreIdentity.id(accountID: account.id, header: first),
            EmailStoreIdentity.id(accountID: account.id, header: second)
        )
    }

    func testStableIdentitySeparatesUIDFallbackByMailbox() {
        let account = makeAccount()
        let inbox = makeHeader(uid: 1, mailbox: .inbox)
        let spam = makeHeader(uid: 1, mailbox: .spam)

        XCTAssertNotEqual(
            EmailStoreIdentity.id(accountID: account.id, header: inbox),
            EmailStoreIdentity.id(accountID: account.id, header: spam)
        )
    }

    @MainActor
    func testPendingItemKeepsUIDAndSelectedMailboxNameTogether() throws {
        let store = makeStore()
        let account = makeAccount()
        let header = makeHeader(uid: 42, mailbox: .spam, mailboxName: "[Gmail]/Spam", gmMessageId: "spam-uid")

        XCTAssertTrue(store.admit(header: header, account: account))

        let item = try XCTUnwrap(store.items.first)
        XCTAssertEqual(item.mailbox, .spam)
        XCTAssertEqual(item.imapIdentity, IMAPMessageIdentity(uid: 42, mailboxName: "[Gmail]/Spam"))
        XCTAssertTrue(item.canMarkAsRead)
    }

    @MainActor
    func testPendingUIDsAreScopedByAccountAndMailbox() {
        let store = makeStore()
        let account = makeAccount()
        let otherAccount = MailAccount(providerID: .gmail, email: "other@example.com")

        XCTAssertTrue(store.admit(header: makeHeader(uid: 1, gmMessageId: "inbox"), account: account))
        XCTAssertTrue(
            store.admit(
                header: makeHeader(uid: 2, mailbox: .spam, mailboxName: "[Gmail]/Spam", gmMessageId: "spam"),
                account: account
            )
        )
        XCTAssertTrue(store.admit(header: makeHeader(uid: 3, gmMessageId: "other"), account: otherAccount))

        XCTAssertEqual(store.pendingUIDs(accountID: account.id, mailbox: .inbox), Set([1]))
        XCTAssertEqual(store.pendingUIDs(accountID: account.id, mailbox: .spam), Set([2]))
    }

    @MainActor
    func testPendingItemWithoutPositiveUIDCannotBeMarkedAsRead() throws {
        let store = makeStore()
        let account = makeAccount()
        let header = makeHeader(uid: 0, gmMessageId: "legacy")

        XCTAssertTrue(store.admit(header: header, account: account))

        let item = try XCTUnwrap(store.items.first)
        XCTAssertNil(item.imapIdentity)
        XCTAssertFalse(item.canMarkAsRead)
    }

    @MainActor
    func testRemoveSpamItemsKeepsInboxItems() {
        let store = makeStore()
        let account = makeAccount()

        XCTAssertTrue(store.admit(header: makeHeader(subject: "Inbox", gmMessageId: "inbox"), account: account))
        XCTAssertTrue(
            store.admit(
                header: makeHeader(mailbox: .spam, subject: "Spam", gmMessageId: "spam"),
                account: account
            )
        )

        XCTAssertTrue(store.removeSpamItems())

        XCTAssertEqual(store.items.map(\.title), ["Inbox"])
        XCTAssertFalse(store.removeSpamItems())
    }

    @MainActor
    func testDismissAndOpenAreIdempotent() {
        let defaults = makeDefaults()
        let account = makeAccount()
        let header = makeHeader(gmMessageId: "1004")
        let id = EmailStoreIdentity.id(accountID: account.id, header: header)
        let store = makeStore(defaults: defaults)

        XCTAssertTrue(store.admit(header: header, account: account))
        store.dismiss(id: id)
        store.dismiss(id: id)
        store.markOpened(id: id)
        store.markOpened(id: id)
        store.markRead(id: id)
        store.markRead(id: id)

        XCTAssertTrue(store.items.isEmpty)

        let relaunchedStore = makeStore(defaults: defaults)
        XCTAssertFalse(relaunchedStore.admit(header: header, account: account))
    }

    func testHandledPersistencePrunesToBoundedRecentSet() {
        let defaults = makeDefaults()
        var timestamp = Date(timeIntervalSince1970: 1)
        let persistence = EmailStorePersistence(
            userDefaults: defaults,
            maxRecordCount: 2,
            now: { timestamp }
        )

        persistence.mark("old", disposition: .dismissed)
        timestamp = Date(timeIntervalSince1970: 2)
        persistence.mark("middle", disposition: .dismissed)
        timestamp = Date(timeIntervalSince1970: 3)
        persistence.mark("new", disposition: .opened)

        XCTAssertFalse(persistence.isHandled("old"))
        XCTAssertTrue(persistence.isHandled("middle"))
        XCTAssertTrue(persistence.isHandled("new"))
    }

    func testHandledPersistenceLoadsRecordsAcrossInstances() {
        let defaults = makeDefaults()
        let firstPersistence = EmailStorePersistence(userDefaults: defaults)

        firstPersistence.mark("persisted", disposition: .opened)

        let secondPersistence = EmailStorePersistence(userDefaults: defaults)
        XCTAssertTrue(secondPersistence.isHandled("persisted"))
    }

    @MainActor
    private func makeStore(defaults: UserDefaults? = nil) -> EmailStore {
        let persistence = EmailStorePersistence(userDefaults: defaults ?? makeDefaults())
        return EmailStore(
            persistence: persistence,
            now: { Date(timeIntervalSince1970: 1_806_000_000) }
        )
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "mailbell.EmailStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func makeAccount() -> MailAccount {
        MailAccount(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            providerID: .gmail,
            email: "account@example.com"
        )
    }

    private func makeHeader(
        uid: Int = 1,
        mailbox: MessageMailbox = .inbox,
        mailboxName: String? = nil,
        subject: String = "Subject",
        gmMessageId: String? = nil,
        gmThreadId: String? = nil,
        messageId: String? = nil,
        bodyPreview: String? = nil
    ) -> MessageHeader {
        MessageHeader(
            uid: uid,
            mailbox: mailbox,
            mailboxName: mailboxName,
            from: "Sender <sender@example.com>",
            subject: subject,
            date: "Tue, 02 Jun 2026 12:00:00 +0000",
            gmThreadId: gmThreadId,
            gmMessageId: gmMessageId,
            messageId: messageId,
            bodyPreview: bodyPreview
        )
    }

    private func makeSnapshot(
        mailbox: MessageMailbox = .inbox,
        mailboxName: String = "INBOX",
        uids: [Int]
    ) -> MailboxUnreadSnapshot {
        MailboxUnreadSnapshot(mailbox: mailbox, mailboxName: mailboxName, unreadUIDs: Set(uids))
    }
}
