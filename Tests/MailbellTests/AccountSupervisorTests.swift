@testable import mailbell
import XCTest

final class AccountSupervisorTests: XCTestCase {
    @MainActor
    func testConnectedStatusClearsPreviousAccountError() async {
        let (supervisor, account) = makeSupervisor()

        supervisor.monitor(
            account.id,
            didChangeStatus: .reconnecting,
            error: "Token refresh unavailable: The Internet connection appears to be offline."
        )
        await Task.yield()

        XCTAssertEqual(
            supervisor.accountStates.first?.lastError,
            "Token refresh unavailable: The Internet connection appears to be offline."
        )

        supervisor.monitor(account.id, didChangeStatus: .connected, error: nil)
        await Task.yield()

        XCTAssertNil(supervisor.accountStates.first?.lastError)
    }

    @MainActor
    func testConnectingStatusDoesNotClearPreviousAccountError() async {
        let (supervisor, account) = makeSupervisor()

        supervisor.monitor(
            account.id,
            didChangeStatus: .reconnecting,
            error: "Token refresh unavailable: The Internet connection appears to be offline."
        )
        await Task.yield()

        supervisor.monitor(account.id, didChangeStatus: .connecting, error: nil)
        await Task.yield()

        XCTAssertEqual(
            supervisor.accountStates.first?.lastError,
            "Token refresh unavailable: The Internet connection appears to be offline."
        )
    }

    @MainActor
    func testConnectedStatusDoesNotClearNotificationError() async {
        let (supervisor, account) = makeSupervisor()

        supervisor.monitor(
            account.id,
            didNotify: makeHeader(),
            result: .unavailable("Notifications unavailable outside app bundle.")
        )
        await Task.yield()

        supervisor.monitor(account.id, didChangeStatus: .connected, error: nil)
        await Task.yield()

        XCTAssertEqual(
            supervisor.accountStates.first?.lastError,
            "Notifications unavailable outside app bundle."
        )
    }

    @MainActor
    func testPostedNotificationClearsPreviousNotificationError() async {
        let (supervisor, account) = makeSupervisor()

        supervisor.monitor(
            account.id,
            didNotify: makeHeader(),
            result: .unavailable("Notifications unavailable outside app bundle.")
        )
        await Task.yield()

        supervisor.monitor(account.id, didNotify: makeHeader(), result: .posted)
        await Task.yield()

        XCTAssertNil(supervisor.accountStates.first?.lastError)
    }

    @MainActor
    func testOAuthSetupMessageUsesConfigProviderError() {
        let (supervisor, _) = makeSupervisor(configProvider: { throw OAuthConfigIssue.missingCredentials })

        XCTAssertEqual(
            supervisor.oauthSetupMessage,
            OAuthConfigIssue.missingCredentials.localizedDescription
        )
    }

    @MainActor
    func testManualRefreshUsesExistingMonitorWithoutStartingDuplicateLoop() {
        var monitors: [SpyMonitor] = []
        let (supervisor, _) = makeSupervisor(monitorFactory: { account, _ in
            let monitor = SpyMonitor(account: account, hasSession: true)
            monitors.append(monitor)
            return monitor
        })

        let monitor = monitors.first
        XCTAssertEqual(monitor?.startCallCount, 1)

        let result = supervisor.refreshNow()

        XCTAssertEqual(result, .requested(accountCount: 1))
        XCTAssertEqual(monitor?.refreshNowCallCount, 1)
        XCTAssertEqual(monitor?.startCallCount, 1)
    }

    @MainActor
    func testManualRefreshReportsNoEnabledAccountsWhenAccountListIsEmpty() {
        let supervisor = makeSupervisor(accounts: [])

        XCTAssertFalse(AccountPresentation.canRefresh(supervisor.accountStates))
        XCTAssertEqual(supervisor.refreshNow(), .noEnabledAccounts)
    }

    @MainActor
    func testManualRefreshReportsNoEnabledAccounts() {
        let disabledAccount = MailAccount(providerID: .gmail, email: "test@example.com", isEnabled: false)
        let (supervisor, _) = makeSupervisor(account: disabledAccount)

        XCTAssertFalse(AccountPresentation.canRefresh(supervisor.accountStates))
        XCTAssertEqual(supervisor.refreshNow(), .noEnabledAccounts)
    }

    @MainActor
    func testManualRefreshIsAvailableWhenAnyAccountIsEnabled() {
        let enabledAccount = MailAccount(providerID: .gmail, email: "enabled@example.com")
        let disabledAccount = MailAccount(providerID: .gmail, email: "disabled@example.com", isEnabled: false)
        let supervisor = makeSupervisor(accounts: [disabledAccount, enabledAccount])

        XCTAssertTrue(AccountPresentation.canRefresh(supervisor.accountStates))
    }

    @MainActor
    func testManualRefreshReportsSignInRequiredWhenSessionIsMissing() {
        let (supervisor, _) = makeSupervisor(monitorFactory: { account, _ in
            SpyMonitor(account: account, hasSession: false)
        })

        XCTAssertEqual(supervisor.refreshNow(), .signInRequired)
        XCTAssertEqual(supervisor.accountStates.first?.status, .reauthRequired)
    }

    @MainActor
    func testMenuIconIsFilledOnlyWhenEmailStoreHasItems() async throws {
        let (supervisor, account) = makeSupervisor()

        XCTAssertEqual(supervisor.menuBarIconSystemImage, "bell")

        let didAdmit = await supervisor.monitor(account.id, shouldNotify: makeHeader(gmMessageId: "icon"))
        XCTAssertTrue(didAdmit)
        XCTAssertEqual(supervisor.menuBarIconSystemImage, "bell.fill")

        let item = try XCTUnwrap(supervisor.emailStoreItems.first)
        supervisor.dismissEmail(id: item.id)

        XCTAssertEqual(supervisor.menuBarIconSystemImage, "bell")
    }

    @MainActor
    func testUnreadSyncPopulatesEmailStoreWithoutPostingNotification() async {
        let (supervisor, account) = makeSupervisor()

        await supervisor.monitor(
            account.id,
            didSyncUnread: [
                makeHeader(uid: 1, subject: "First unread", gmMessageId: "first-unread"),
                makeHeader(uid: 2, subject: "Second unread", gmMessageId: "second-unread")
            ]
        )

        XCTAssertEqual(Set(supervisor.emailStoreItems.map(\.title)), Set(["First unread", "Second unread"]))
        XCTAssertNil(supervisor.accountStates.first?.lastError)
    }

    @MainActor
    func testNotificationOpenActionRemovesEmailFromStore() async throws {
        var openedURLs: [URL] = []
        var openedAccountIDs: [UUID?] = []
        let (supervisor, account) = makeSupervisor(webmailOpen: { url, account in
            openedURLs.append(url)
            openedAccountIDs.append(account?.id)
            return .opened
        })

        let header = makeHeader(gmMessageId: "notification-open", gmThreadId: "123456789")
        let didAdmit = await supervisor.monitor(account.id, shouldNotify: header)
        XCTAssertTrue(didAdmit)

        let item = try XCTUnwrap(supervisor.emailStoreItems.first)
        await supervisor.openEmail(id: item.id, accountID: account.id, url: item.webmailURL)

        XCTAssertEqual(openedURLs, [item.webmailURL])
        XCTAssertEqual(openedAccountIDs, [account.id])
        XCTAssertTrue(supervisor.emailStoreItems.isEmpty)
        let didReadmit = await supervisor.monitor(account.id, shouldNotify: header)
        XCTAssertFalse(didReadmit)
    }

    @MainActor
    func testOpenGmailPassesSelectedAccountToWebmailOpener() async {
        let first = MailAccount(providerID: .gmail, email: "first@example.com")
        let second = MailAccount(providerID: .gmail, email: "second@example.com")
        var openedURLs: [URL] = []
        var openedAccountIDs: [UUID?] = []
        let supervisor = makeSupervisor(accounts: [first, second], webmailOpen: { url, account in
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
        let (supervisor, account) = makeSupervisor()
        let header = makeHeader(gmMessageId: "notification-dismiss")

        let didAdmit = await supervisor.monitor(account.id, shouldNotify: header)
        XCTAssertTrue(didAdmit)
        let item = try XCTUnwrap(supervisor.emailStoreItems.first)

        supervisor.dismissEmail(id: item.id)
        supervisor.dismissEmail(id: item.id)

        XCTAssertTrue(supervisor.emailStoreItems.isEmpty)
        let didReadmit = await supervisor.monitor(account.id, shouldNotify: header)
        XCTAssertFalse(didReadmit)
    }

    @MainActor
    private func makeSupervisor(
        configProvider: @escaping () throws -> OAuthConfig = {
            OAuthConfig(
                clientID: "dummy-local-client-id.apps.googleusercontent.com",
                clientSecret: "dummy-local-client-secret"
            )
        },
        account: MailAccount = MailAccount(providerID: .gmail, email: "test@example.com"),
        monitorFactory: @escaping (MailAccount, OAuthConfig) -> any AccountMonitoring = { account, _ in
            SpyMonitor(account: account, hasSession: false)
        },
        webmailOpen: @escaping @MainActor (URL, MailAccount?) async -> WebmailOpenOutcome = { _, _ in .opened }
    ) -> (AccountSupervisor, MailAccount) {
        (
            makeSupervisor(
                accounts: [account],
                configProvider: configProvider,
                monitorFactory: monitorFactory,
                webmailOpen: webmailOpen
            ),
            account
        )
    }

    @MainActor
    private func makeSupervisor(
        accounts: [MailAccount],
        configProvider: @escaping () throws -> OAuthConfig = {
            OAuthConfig(
                clientID: "dummy-local-client-id.apps.googleusercontent.com",
                clientSecret: "dummy-local-client-secret"
            )
        },
        monitorFactory: @escaping (MailAccount, OAuthConfig) -> any AccountMonitoring = { account, _ in
            SpyMonitor(account: account, hasSession: false)
        },
        webmailOpen: @escaping @MainActor (URL, MailAccount?) async -> WebmailOpenOutcome = { _, _ in .opened }
    ) -> AccountSupervisor {
        let suiteName = "mailbell.AccountSupervisorTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = AccountStore(userDefaults: defaults)
        store.saveAccounts(accounts)
        let emailStore = EmailStore(persistence: EmailStorePersistence(userDefaults: defaults))
        return AccountSupervisor(
            configProvider: configProvider,
            accountStore: store,
            emailStore: emailStore,
            monitorFactory: monitorFactory,
            webmailOpen: webmailOpen
        )
    }

    private func makeHeader(
        uid: Int = 1,
        subject: String = "Subject",
        gmMessageId: String? = nil,
        gmThreadId: String? = nil
    ) -> MessageHeader {
        MessageHeader(
            uid: uid,
            from: "sender@example.com",
            subject: subject,
            date: "",
            gmThreadId: gmThreadId,
            gmMessageId: gmMessageId
        )
    }
}

private final class SpyMonitor: AccountMonitoring {
    weak var delegate: MailMonitorDelegate?
    private(set) var account: MailAccount
    var hasSession: Bool
    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0
    private(set) var forceReconnectCallCount = 0
    private(set) var refreshNowCallCount = 0

    init(account: MailAccount, hasSession: Bool) {
        self.account = account
        self.hasSession = hasSession
    }

    func updateAccount(_ account: MailAccount) {
        self.account = account
    }

    func start() {
        startCallCount += 1
    }

    func stop(clearSession _: Bool) {
        stopCallCount += 1
    }

    func forceReconnect() {
        forceReconnectCallCount += 1
    }

    func refreshNow() {
        refreshNowCallCount += 1
    }
}
