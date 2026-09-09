@testable import mailbell
import XCTest

/// How the supervisor moves mail through the review queue: admission,
/// reconciliation, the notification actions, Spam, and sign-in expiry.

final class AccountSupervisorQueueTests: XCTestCase {
    @MainActor
    func testUnreadSyncPopulatesEmailStoreWithoutPostingNotification() async {
        let (supervisor, account) = SupervisorFixture.makeSupervisor()

        await supervisor.monitor(
            account.id,
            didReconcileUnread: [SupervisorFixture.makeSnapshot(uids: [1, 2])],
            fetchedHeaders: [
                SupervisorFixture.makeHeader(uid: 1, subject: "First unread", gmMessageId: "first-unread"),
                SupervisorFixture.makeHeader(uid: 2, subject: "Second unread", gmMessageId: "second-unread")
            ]
        )

        XCTAssertEqual(Set(supervisor.emailStoreItems.map(\.title)), Set(["First unread", "Second unread"]))
        XCTAssertNil(supervisor.accountStates.first?.lastError)
    }

    @MainActor
    func testUnreadSyncRemovesExternallyReadPendingAndUpdatesMenuIcon() async {
        let (supervisor, account) = SupervisorFixture.makeSupervisor()
        let header = SupervisorFixture.makeHeader(uid: 1, subject: "Read in Gmail", gmMessageId: "read-in-gmail")

        let didAdmit = await SupervisorFixture.admit(header, into: supervisor, account: account)
        XCTAssertTrue(didAdmit)
        XCTAssertEqual(supervisor.emailStoreItems.count, 1)
        XCTAssertEqual(supervisor.menuBarIconSystemImage, "bell.fill")

        await supervisor.monitor(account.id, didReconcileUnread: [SupervisorFixture.makeSnapshot(
            uids: [])],
            fetchedHeaders: []
        )

        XCTAssertTrue(supervisor.emailStoreItems.isEmpty)
        XCTAssertEqual(supervisor.menuBarIconSystemImage, "bell")
    }

    @MainActor
    func testNotificationOpenActionRemovesEmailFromStore() async throws {
        var openedURLs: [URL] = []
        var openedAccountIDs: [UUID?] = []
        let (supervisor, account) = SupervisorFixture.makeSupervisor(webmailOpen: { url, account in
            openedURLs.append(url)
            openedAccountIDs.append(account?.id)
            return .opened
        })

        let header = SupervisorFixture.makeHeader(gmMessageId: "notification-open", gmThreadId: "123456789")
        let didAdmit = await SupervisorFixture.admit(header, into: supervisor, account: account)
        XCTAssertTrue(didAdmit)

        let item = try XCTUnwrap(supervisor.emailStoreItems.first)
        await supervisor.openEmail(id: item.id, accountID: account.id, url: item.webmailURL)

        XCTAssertEqual(openedURLs, [item.webmailURL])
        XCTAssertEqual(openedAccountIDs, [account.id])
        XCTAssertTrue(supervisor.emailStoreItems.isEmpty)
        let didReadmit = await SupervisorFixture.admit(header, into: supervisor, account: account)
        XCTAssertFalse(didReadmit)
    }

    @MainActor
    func testOpenGmailPassesSelectedAccountToWebmailOpener() async {
        let first = MailAccount(providerID: .gmail, email: "first@example.com")
        let second = MailAccount(providerID: .gmail, email: "second@example.com")
        var openedURLs: [URL] = []
        var openedAccountIDs: [UUID?] = []
        let supervisor = SupervisorFixture.makeSupervisor(accounts: [first, second], webmailOpen: { url, account in
            openedURLs.append(url)
            openedAccountIDs.append(account?.id)
            return .opened
        })

        await supervisor.openGmail(accountID: second.id)

        XCTAssertEqual(openedURLs, [MailProviderRegistry.provider(for: .gmail).webmailURL(for: second)])
        XCTAssertEqual(openedAccountIDs, [second.id])
    }

    @MainActor
    func testNotificationDismissActionRemovesEmailFromStore() async throws {
        let (supervisor, account) = SupervisorFixture.makeSupervisor()
        let header = SupervisorFixture.makeHeader(gmMessageId: "notification-dismiss")

        let didAdmit = await SupervisorFixture.admit(header, into: supervisor, account: account)
        XCTAssertTrue(didAdmit)
        let item = try XCTUnwrap(supervisor.emailStoreItems.first)

        supervisor.dismissEmail(id: item.id)
        supervisor.dismissEmail(id: item.id)

        XCTAssertTrue(supervisor.emailStoreItems.isEmpty)
        let didReadmit = await SupervisorFixture.admit(header, into: supervisor, account: account)
        XCTAssertFalse(didReadmit)
    }

    @MainActor
    func testDismissPersistenceFailureKeepsEmailVisibleAndSurfacesAccountError() async throws {
        let account = MailAccount(providerID: .gmail, email: "test@example.com")
        let defaults = SupervisorFixture.makeDefaults()
        var shouldFail = false
        let emailStore = EmailStore(
            persistence: EmailStorePersistence(
                userDefaults: defaults,
                saveData: { data, key in
                    if shouldFail {
                        throw EmailStorePersistence.PersistenceError.saveFailed("disk full")
                    }
                    defaults.set(data, forKey: key)
                }
            )
        )
        let supervisor = SupervisorFixture.makeSupervisor(accounts: [account], emailStore: emailStore)
        let header = SupervisorFixture.makeHeader(gmMessageId: "dismiss-persistence-failure")

        let didAdmit = await SupervisorFixture.admit(header, into: supervisor, account: account)
        XCTAssertTrue(didAdmit)
        let item = try XCTUnwrap(supervisor.emailStoreItems.first)
        shouldFail = true

        supervisor.dismissEmail(id: item.id)

        XCTAssertEqual(supervisor.emailStoreItems.map(\.id), [item.id])
        XCTAssertEqual(
            supervisor.accountStates.first?.lastError,
            "Could not save handled-message history: disk full"
        )
    }

    @MainActor
    func testOpenPersistenceFailureKeepsEmailVisibleAndSurfacesAccountError() async throws {
        let account = MailAccount(providerID: .gmail, email: "test@example.com")
        let defaults = SupervisorFixture.makeDefaults()
        var shouldFail = false
        let emailStore = EmailStore(
            persistence: EmailStorePersistence(
                userDefaults: defaults,
                saveData: { data, key in
                    if shouldFail {
                        throw EmailStorePersistence.PersistenceError.saveFailed("disk full")
                    }
                    defaults.set(data, forKey: key)
                }
            )
        )
        let supervisor = SupervisorFixture.makeSupervisor(accounts: [account], emailStore: emailStore)
        let header = SupervisorFixture.makeHeader(gmMessageId: "open-persistence-failure")

        let didAdmit = await SupervisorFixture.admit(header, into: supervisor, account: account)
        XCTAssertTrue(didAdmit)
        let item = try XCTUnwrap(supervisor.emailStoreItems.first)
        shouldFail = true

        await supervisor.openEmail(id: item.id, accountID: account.id, url: item.webmailURL)

        XCTAssertEqual(supervisor.emailStoreItems.map(\.id), [item.id])
        XCTAssertEqual(
            supervisor.accountStates.first?.lastError,
            "Could not save handled-message history: disk full"
        )
    }

    @MainActor
    func testSpamHeaderIsIgnoredWhenIncludeSpamIsDisabled() async {
        let (supervisor, account) = SupervisorFixture.makeSupervisor(includeSpam: false)

        let didAdmit = await SupervisorFixture.admit(
            SupervisorFixture.makeHeader(mailbox: .spam, gmMessageId: "spam-disabled"),
            into: supervisor,
            account: account
        )

        XCTAssertFalse(didAdmit)
        XCTAssertTrue(supervisor.emailStoreItems.isEmpty)
    }

    @MainActor
    func testSpamHeaderIsAdmittedWhenIncludeSpamIsEnabled() async throws {
        let (supervisor, account) = SupervisorFixture.makeSupervisor(includeSpam: true)

        let didAdmit = await SupervisorFixture.admit(
            SupervisorFixture.makeHeader(mailbox: .spam, gmMessageId: "spam-enabled"),
            into: supervisor,
            account: account
        )

        XCTAssertTrue(didAdmit)
        let item = try XCTUnwrap(supervisor.emailStoreItems.first)
        XCTAssertEqual(item.mailbox, .spam)
    }

    @MainActor
    func testDisablingSpamRemovesSpamItemsAndUpdatesMonitors() async {
        var monitors: [SpyMonitor] = []
        let (supervisor, account) = SupervisorFixture.makeSupervisor(
            includeSpam: true,
            monitorFactory: { account, _, includeSpam in
            let monitor = SpyMonitor(account: account, hasSession: true, includeSpam: includeSpam)
            monitors.append(monitor)
            return monitor
        })

        _ = await SupervisorFixture.admit(
            SupervisorFixture.makeHeader(mailbox: .spam, gmMessageId: "spam"),
            into: supervisor,
            account: account
        )

        supervisor.setIncludeSpam(false)

        XCTAssertTrue(supervisor.emailStoreItems.isEmpty)
        XCTAssertEqual(monitors.first?.includeSpam, false)
    }

    @MainActor
    func testSignInExpiryNotifiesOncePerTransition() async {
        var notified: [String] = []
        let (supervisor, account) = SupervisorFixture.makeSupervisor(
            signInNeededNotifier: { notified.append($0.email) }
        )

        supervisor.monitor(account.id, didChangeStatus: .connected, error: nil)
        await Task.yield()
        XCTAssertTrue(notified.isEmpty)

        supervisor.monitor(account.id, didChangeStatus: .reauthRequired, error: "Token revoked")
        await Task.yield()
        XCTAssertEqual(notified, [account.email])

        // A later update while the account is still waiting must not alert again.
        supervisor.monitor(account.id, didNotify: SupervisorFixture.makeHeader(), result: .posted)
        supervisor.monitor(account.id, didChangeStatus: .reauthRequired, error: "Token revoked")
        await Task.yield()
        XCTAssertEqual(notified, [account.email])
    }

    @MainActor
    func testSignInExpiryDoesNotNotifyForDisabledAccount() async {
        let disabledAccount = MailAccount(providerID: .gmail, email: "test@example.com", isEnabled: false)
        var notified: [String] = []
        let (supervisor, account) = SupervisorFixture.makeSupervisor(
            account: disabledAccount,
            signInNeededNotifier: { notified.append($0.email) }
        )

        supervisor.monitor(account.id, didChangeStatus: .reauthRequired, error: "Token revoked")
        await Task.yield()

        XCTAssertTrue(notified.isEmpty)
    }
}
