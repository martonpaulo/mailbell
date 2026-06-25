@testable import mailbell
import XCTest

// swiftlint:disable:next type_body_length
final class EmailStoreTests: XCTestCase {
    @MainActor
    func testAdmitsUnreadEmailWhenNotHandled() throws {
        let store = makeStore()
        let account = makeAccount()
        let header = makeHeader(gmMessageId: "1001")

        XCTAssertTrue(try store.admit(header: header, account: account))

        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.items.first?.title, "Subject")
        XCTAssertEqual(store.items.first?.sender, "Sender <sender@example.com>")
        XCTAssertNil(store.items.first?.bodyPreview)
        XCTAssertEqual(store.items.first?.imapIdentity, IMAPMessageIdentity(uid: 1, mailboxName: "INBOX"))
        XCTAssertTrue(store.items.first?.canMarkAsRead == true)
    }

    @MainActor
    func testDismissedEmailIsExcludedAfterRelaunch() throws {
        let defaults = makeDefaults()
        let account = makeAccount()
        let header = makeHeader(gmMessageId: "1002")
        let id = EmailStoreIdentity.id(accountID: account.id, header: header)

        let store = makeStore(defaults: defaults)
        XCTAssertTrue(try store.admit(header: header, account: account))
        try store.dismiss(id: id)

        let relaunchedStore = makeStore(defaults: defaults)
        XCTAssertFalse(try relaunchedStore.admit(header: header, account: account))
        XCTAssertTrue(relaunchedStore.items.isEmpty)
    }

    @MainActor
    func testOpenedEmailIsExcludedAfterRelaunch() throws {
        let defaults = makeDefaults()
        let account = makeAccount()
        let header = makeHeader(gmMessageId: "1003")
        let id = EmailStoreIdentity.id(accountID: account.id, header: header)

        let store = makeStore(defaults: defaults)
        XCTAssertTrue(try store.admit(header: header, account: account))
        try store.markOpened(id: id)

        let relaunchedStore = makeStore(defaults: defaults)
        XCTAssertFalse(try relaunchedStore.admit(header: header, account: account))
        XCTAssertTrue(relaunchedStore.items.isEmpty)
    }

    @MainActor
    func testMarkedReadEmailIsExcludedAfterRelaunch() throws {
        let defaults = makeDefaults()
        let account = makeAccount()
        let header = makeHeader(gmMessageId: "1005")
        let id = EmailStoreIdentity.id(accountID: account.id, header: header)

        let store = makeStore(defaults: defaults)
        XCTAssertTrue(try store.admit(header: header, account: account))
        try store.markRead(id: id)

        let relaunchedStore = makeStore(defaults: defaults)
        XCTAssertFalse(try relaunchedStore.admit(header: header, account: account))
        XCTAssertTrue(relaunchedStore.items.isEmpty)
    }

    @MainActor
    func testUnreadSyncAfterRelaunchExcludesDismissedAndRestoresProviderUnreadEmails() throws {
        let defaults = makeDefaults()
        let account = makeAccount()
        let dismissedHeader = makeHeader(uid: 1, gmMessageId: "dismissed")
        let openedHeader = makeHeader(uid: 2, subject: "Opened", gmMessageId: "opened")
        let markedReadHeader = makeHeader(uid: 3, subject: "Marked Read", gmMessageId: "marked-read")
        let unreadHeader = makeHeader(uid: 4, subject: "Unread", gmMessageId: "unread")

        let store = makeStore(defaults: defaults)
        try store.dismiss(id: EmailStoreIdentity.id(accountID: account.id, header: dismissedHeader))
        try store.markOpened(id: EmailStoreIdentity.id(accountID: account.id, header: openedHeader))
        try store.markRead(id: EmailStoreIdentity.id(accountID: account.id, header: markedReadHeader))

        let relaunchedStore = makeStore(defaults: defaults)
        let didChange = try relaunchedStore.reconcileUnread(
            snapshots: [makeSnapshot(uids: [1, 2, 3, 4])],
            fetchedHeaders: [dismissedHeader, openedHeader, markedReadHeader, unreadHeader],
            account: account
        )

        XCTAssertTrue(didChange)
        XCTAssertEqual(Set(relaunchedStore.items.map(\.title)), Set(["Opened", "Marked Read", "Unread"]))
    }

    @MainActor
    func testUnreadSyncReplacesAccountItemsWithCurrentUnreadHeaders() throws {
        let store = makeStore()
        let account = makeAccount()
        let firstHeader = makeHeader(uid: 1, subject: "Read elsewhere", gmMessageId: "read-elsewhere")
        let secondHeader = makeHeader(uid: 2, subject: "Still unread", gmMessageId: "still-unread")

        XCTAssertTrue(
            try store.reconcileUnread(
                snapshots: [makeSnapshot(uids: [1, 2])],
                fetchedHeaders: [firstHeader, secondHeader],
                account: account
            )
        )
        XCTAssertEqual(store.items.map(\.title), ["Read elsewhere", "Still unread"])

        XCTAssertTrue(
            try store.reconcileUnread(
                snapshots: [makeSnapshot(uids: [2])],
                fetchedHeaders: [],
                account: account
            )
        )
        XCTAssertEqual(store.items.map(\.title), ["Still unread"])
    }

    @MainActor
    func testUnreadSyncRemovesExternallyReadMessageInsideThreadGroup() throws {
        let store = makeStore()
        let account = makeAccount()
        let firstHeader = makeHeader(uid: 1, subject: "Read elsewhere", gmMessageId: "message-1", gmThreadId: "thread-1")
        let secondHeader = makeHeader(uid: 2, subject: "Still unread", gmMessageId: "message-2", gmThreadId: "thread-1")

        XCTAssertTrue(try store.admit(header: firstHeader, account: account))
        XCTAssertTrue(try store.admit(header: secondHeader, account: account))

        XCTAssertTrue(
            try store.reconcileUnread(
                snapshots: [makeSnapshot(uids: [2])],
                fetchedHeaders: [],
                account: account
            )
        )

        XCTAssertEqual(store.items.map(\.title), ["Still unread"])
        XCTAssertEqual(store.pendingUIDs(accountID: account.id, mailbox: .inbox), Set([2]))
    }

    @MainActor
    func testUnreadSyncIsIdempotentForSameProviderState() throws {
        let store = makeStore()
        let account = makeAccount()
        let header = makeHeader(uid: 1, subject: "Still unread", gmMessageId: "still-unread")

        XCTAssertTrue(
            try store.reconcileUnread(
                snapshots: [makeSnapshot(uids: [1])],
                fetchedHeaders: [header],
                account: account
            )
        )
        XCTAssertFalse(
            try store.reconcileUnread(
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
            try store.reconcileUnread(
                snapshots: [makeSnapshot(uids: [1])],
                fetchedHeaders: [inboxHeader],
                account: account
            )
        )
        let original = try XCTUnwrap(store.items.first)

        XCTAssertTrue(
            try store.reconcileUnread(
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
        XCTAssertEqual(updated.title, "(SPAM) Moved to spam")
        XCTAssertEqual(updated.mailbox, .spam)
        XCTAssertEqual(updated.imapIdentity, IMAPMessageIdentity(uid: 42, mailboxName: "[Gmail]/Spam"))
    }

    @MainActor
    func testDuplicateEmailsAreDeduplicatedByStableID() throws {
        let store = makeStore()
        let account = makeAccount()

        let firstHeader = makeHeader(uid: 1, subject: "First", gmMessageId: "same")
        let duplicateHeader = makeHeader(uid: 2, subject: "Second", gmMessageId: "same")

        XCTAssertTrue(try store.admit(header: firstHeader, account: account))
        XCTAssertFalse(try store.admit(header: duplicateHeader, account: account))

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

        XCTAssertTrue(try store.admit(header: firstHeader, account: account))
        XCTAssertTrue(try store.admit(header: secondHeader, account: account))

        let item = try XCTUnwrap(store.items.first)
        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(item.title, "First")
        XCTAssertEqual(item.bodyPreview, "First preview")
        XCTAssertEqual(item.bodyPreviewLines, ["First preview"])
        XCTAssertEqual(
            store.pendingUIDs(accountID: account.id, mailbox: .inbox),
            Set([1, 2])
        )
        XCTAssertEqual(store.pendingCountsByAccountID[account.id], 1)
    }

    @MainActor
    func testThreadGroupUsesFirstAdmittedEmailWhenUIDsTieOnReceivedAt() throws {
        let store = makeStore()
        let account = makeAccount()
        let firstAdmittedHeader = makeHeader(
            uid: 2,
            subject: "First notified",
            gmMessageId: "message-2",
            gmThreadId: "thread-1",
            bodyPreview: "First notified preview"
        )
        let laterAdmittedHeader = makeHeader(
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
        let defaults = makeDefaults()
        let store = makeStore(defaults: defaults)
        let account = makeAccount()
        let firstHeader = makeHeader(uid: 1, gmMessageId: "message-1", gmThreadId: "thread-1")
        let secondHeader = makeHeader(uid: 2, gmMessageId: "message-2", gmThreadId: "thread-1")
        let futureHeader = makeHeader(uid: 3, gmMessageId: "message-3", gmThreadId: "thread-1")

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
        let store = makeStore()
        let account = makeAccount()
        let firstHeader = makeHeader(uid: 1, subject: "First", gmMessageId: "message-1", gmThreadId: "thread-1")
        let secondHeader = makeHeader(uid: 2, subject: "Second", gmMessageId: "message-2", gmThreadId: "thread-1")

        XCTAssertTrue(try store.admit(header: firstHeader, account: account))
        XCTAssertTrue(try store.admit(header: secondHeader, account: account))

        let secondID = EmailStoreIdentity.id(accountID: account.id, header: secondHeader)
        let firstItem = try XCTUnwrap(store.firstItemInGroup(containing: secondID))
        XCTAssertEqual(firstItem.title, "First")
    }

    func testStableIdentityPrefersProviderIDsOverSubject() throws {
        let account = makeAccount()
        let first = makeHeader(uid: 1, subject: "First", gmMessageId: "provider-id")
        let second = makeHeader(uid: 2, subject: "Second", gmMessageId: "provider-id")

        XCTAssertEqual(
            EmailStoreIdentity.id(accountID: account.id, header: first),
            EmailStoreIdentity.id(accountID: account.id, header: second)
        )
    }

    func testStableIdentitySeparatesUIDFallbackByMailbox() throws {
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

        XCTAssertTrue(try store.admit(header: header, account: account))

        let item = try XCTUnwrap(store.items.first)
        XCTAssertEqual(item.mailbox, .spam)
        XCTAssertEqual(item.imapIdentity, IMAPMessageIdentity(uid: 42, mailboxName: "[Gmail]/Spam"))
        XCTAssertTrue(item.canMarkAsRead)
    }

    @MainActor
    func testPendingUIDsAreScopedByAccountAndMailbox() throws {
        let store = makeStore()
        let account = makeAccount()
        let otherAccount = MailAccount(providerID: .gmail, email: "other@example.com")

        XCTAssertTrue(try store.admit(header: makeHeader(uid: 1, gmMessageId: "inbox"), account: account))
        XCTAssertTrue(
            try store.admit(
                header: makeHeader(uid: 2, mailbox: .spam, mailboxName: "[Gmail]/Spam", gmMessageId: "spam"),
                account: account
            )
        )
        XCTAssertTrue(try store.admit(header: makeHeader(uid: 3, gmMessageId: "other"), account: otherAccount))

        XCTAssertEqual(store.pendingUIDs(accountID: account.id, mailbox: .inbox), Set([1]))
        XCTAssertEqual(store.pendingUIDs(accountID: account.id, mailbox: .spam), Set([2]))
    }

    @MainActor
    func testPendingItemWithoutPositiveUIDCannotBeMarkedAsRead() throws {
        let store = makeStore()
        let account = makeAccount()
        let header = makeHeader(uid: 0, gmMessageId: "legacy")

        XCTAssertTrue(try store.admit(header: header, account: account))

        let item = try XCTUnwrap(store.items.first)
        XCTAssertNil(item.imapIdentity)
        XCTAssertFalse(item.canMarkAsRead)
    }

    @MainActor
    func testRemoveSpamItemsKeepsInboxItems() throws {
        let store = makeStore()
        let account = makeAccount()

        XCTAssertTrue(try store.admit(header: makeHeader(subject: "Inbox", gmMessageId: "inbox"), account: account))
        XCTAssertTrue(
            try store.admit(
                header: makeHeader(mailbox: .spam, subject: "Spam", gmMessageId: "spam"),
                account: account
            )
        )

        XCTAssertTrue(store.removeSpamItems())

        XCTAssertEqual(store.items.map(\.title), ["Inbox"])
        XCTAssertFalse(store.removeSpamItems())
    }

    @MainActor
    func testDismissAndOpenAreIdempotent() throws {
        let defaults = makeDefaults()
        let account = makeAccount()
        let header = makeHeader(gmMessageId: "1004")
        let id = EmailStoreIdentity.id(accountID: account.id, header: header)
        let store = makeStore(defaults: defaults)

        XCTAssertTrue(try store.admit(header: header, account: account))
        try store.dismiss(id: id)
        try store.dismiss(id: id)
        try store.markOpened(id: id)
        try store.markOpened(id: id)
        try store.markRead(id: id)
        try store.markRead(id: id)

        XCTAssertTrue(store.items.isEmpty)

        let relaunchedStore = makeStore(defaults: defaults)
        XCTAssertFalse(try relaunchedStore.admit(header: header, account: account))
    }

    func testHandledPersistencePrunesToBoundedRecentSet() throws {
        let defaults = makeDefaults()
        var timestamp = Date(timeIntervalSince1970: 1)
        let persistence = EmailStorePersistence(
            userDefaults: defaults,
            maxRecordCount: 2,
            now: { timestamp }
        )

        try persistence.mark("old", disposition: .dismissed)
        timestamp = Date(timeIntervalSince1970: 2)
        try persistence.mark("middle", disposition: .dismissed)
        timestamp = Date(timeIntervalSince1970: 3)
        try persistence.mark("new", disposition: .opened)

        XCTAssertFalse(try persistence.isHandled("old"))
        XCTAssertTrue(try persistence.isHandled("middle"))
        XCTAssertTrue(try persistence.isHandled("new"))
    }

    func testHandledPersistenceLoadsRecordsAcrossInstances() throws {
        let defaults = makeDefaults()
        let firstPersistence = EmailStorePersistence(userDefaults: defaults)

        try firstPersistence.mark("persisted", disposition: .opened)

        let secondPersistence = EmailStorePersistence(userDefaults: defaults)
        XCTAssertTrue(try secondPersistence.isHandled("persisted"))
    }

    func testCorruptHandledPersistenceIsBackedUpOnceAndRecoveredWithWarning() throws {
        let defaults = makeDefaults()
        let corrupt = Data("not-json".utf8)
        defaults.set(corrupt, forKey: EmailStorePersistence.recordsKey)
        let persistence = EmailStorePersistence(userDefaults: defaults)

        XCTAssertFalse(try persistence.isHandled("anything"))

        XCTAssertEqual(defaults.data(forKey: EmailStorePersistence.corruptBackupKey), corrupt)
        let activeData = try XCTUnwrap(defaults.data(forKey: EmailStorePersistence.recordsKey))
        let decoded = try JSONDecoder().decode([String: String].self, from: activeData)
        XCTAssertTrue(decoded.isEmpty)
        XCTAssertEqual(persistence.takeRecoveryWarning(), EmailStorePersistence.recoveryWarning)
        XCTAssertNil(persistence.takeRecoveryWarning())

        let reloadedPersistence = EmailStorePersistence(userDefaults: defaults)
        XCTAssertFalse(try reloadedPersistence.isHandled("anything"))
        XCTAssertNil(reloadedPersistence.takeRecoveryWarning())
    }

    func testCorruptHandledPersistenceBackupFailurePreservesOriginalPayload() {
        let defaults = makeDefaults()
        let corrupt = Data("not-json".utf8)
        defaults.set(corrupt, forKey: EmailStorePersistence.recordsKey)
        let persistence = EmailStorePersistence(
            userDefaults: defaults,
            saveData: { _, key in
                if key == EmailStorePersistence.corruptBackupKey {
                    throw EmailStorePersistence.PersistenceError.saveFailed("disk full")
                }
            }
        )

        XCTAssertThrowsError(try persistence.isHandled("anything")) { error in
            XCTAssertEqual(error.localizedDescription, "Could not save handled-message history: disk full")
        }
        XCTAssertEqual(defaults.data(forKey: EmailStorePersistence.recordsKey), corrupt)
        XCTAssertNil(defaults.data(forKey: EmailStorePersistence.corruptBackupKey))
        XCTAssertNil(persistence.takeRecoveryWarning())
    }

    @MainActor
    func testDismissSaveFailureLeavesDurableCacheAndVisiblePendingStateUnchanged() throws {
        let defaults = makeDefaults()
        var shouldFail = false
        let persistence = EmailStorePersistence(
            userDefaults: defaults,
            saveData: { data, key in
                if shouldFail {
                    throw EmailStorePersistence.PersistenceError.saveFailed("disk full")
                }
                defaults.set(data, forKey: key)
            }
        )
        let store = EmailStore(persistence: persistence)
        let account = makeAccount()
        let header = makeHeader(gmMessageId: "atomic-dismiss")
        let id = EmailStoreIdentity.id(accountID: account.id, header: header)

        XCTAssertTrue(try store.admit(header: header, account: account))
        shouldFail = true

        XCTAssertThrowsError(try store.dismiss(id: id)) { error in
            XCTAssertEqual(error.localizedDescription, "Could not save handled-message history: disk full")
        }
        XCTAssertEqual(store.items.map(\.id), [id])
        let relaunchedStore = makeStore(defaults: defaults)
        XCTAssertTrue(try relaunchedStore.admit(header: header, account: account))
    }

    @MainActor
    func testAccountRecordRemovalFailureLeavesVisibleItemsUntouched() throws {
        let defaults = makeDefaults()
        var shouldFail = false
        let persistence = EmailStorePersistence(
            userDefaults: defaults,
            saveData: { data, key in
                if shouldFail {
                    throw EmailStorePersistence.PersistenceError.saveFailed("disk full")
                }
                defaults.set(data, forKey: key)
            }
        )
        let store = EmailStore(persistence: persistence)
        let account = makeAccount()
        let handledHeader = makeHeader(gmMessageId: "account-removal-handled")
        let visibleHeader = makeHeader(uid: 2, gmMessageId: "account-removal-visible")

        XCTAssertTrue(try store.admit(header: handledHeader, account: account))
        try store.dismiss(id: EmailStoreIdentity.id(accountID: account.id, header: handledHeader))
        XCTAssertFalse(try store.admit(header: handledHeader, account: account))
        XCTAssertTrue(try store.admit(header: visibleHeader, account: account))
        let visibleID = EmailStoreIdentity.id(accountID: account.id, header: visibleHeader)
        shouldFail = true

        XCTAssertThrowsError(try store.removeAccountRecords(accountID: account.id)) { error in
            XCTAssertEqual(error.localizedDescription, "Could not save handled-message history: disk full")
        }
        XCTAssertEqual(store.items.map(\.id), [visibleID])
        let relaunchedStore = makeStore(defaults: defaults)
        XCTAssertFalse(try relaunchedStore.admit(header: handledHeader, account: account))
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
