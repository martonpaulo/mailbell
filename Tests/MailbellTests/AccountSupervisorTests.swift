@testable import mailbell
import XCTest

final class AccountSupervisorTests: XCTestCase {
    @MainActor
    func testConnectedStatusClearsPreviousAccountError() async {
        let (supervisor, account) = SupervisorFixture.makeSupervisor()

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
        let (supervisor, account) = SupervisorFixture.makeSupervisor()

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
        let (supervisor, account) = SupervisorFixture.makeSupervisor()

        supervisor.monitor(
            account.id,
            didNotify: SupervisorFixture.makeHeader(),
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
        let (supervisor, account) = SupervisorFixture.makeSupervisor()

        supervisor.monitor(
            account.id,
            didNotify: SupervisorFixture.makeHeader(),
            result: .unavailable("Notifications unavailable outside app bundle.")
        )
        await Task.yield()

        supervisor.monitor(account.id, didNotify: SupervisorFixture.makeHeader(), result: .posted)
        await Task.yield()

        XCTAssertNil(supervisor.accountStates.first?.lastError)
    }

    @MainActor
    func testOAuthSetupMessageUsesConfigProviderError() {
        let (supervisor, _) = SupervisorFixture.makeSupervisor(
            configProvider: { throw OAuthConfigIssue.missingCredentials }
        )

        XCTAssertEqual(
            supervisor.oauthSetupMessage,
            OAuthConfigIssue.missingCredentials.localizedDescription
        )
    }

    @MainActor
    func testManualRefreshUsesExistingMonitorWithoutStartingDuplicateLoop() {
        var monitors: [SpyMonitor] = []
        let (supervisor, _) = SupervisorFixture.makeSupervisor(monitorFactory: { account, _, includeSpam in
            let monitor = SpyMonitor(account: account, hasSession: true, includeSpam: includeSpam)
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
        let supervisor = SupervisorFixture.makeSupervisor(accounts: [])

        XCTAssertFalse(AccountPresentation.canRefresh(supervisor.accountStates))
        XCTAssertEqual(supervisor.refreshNow(), .noEnabledAccounts)
    }

    @MainActor
    func testManualRefreshReportsNoEnabledAccounts() {
        let disabledAccount = MailAccount(providerID: .gmail, email: "test@example.com", isEnabled: false)
        let (supervisor, _) = SupervisorFixture.makeSupervisor(account: disabledAccount)

        XCTAssertFalse(AccountPresentation.canRefresh(supervisor.accountStates))
        XCTAssertEqual(supervisor.refreshNow(), .noEnabledAccounts)
    }

    @MainActor
    func testManualRefreshIsAvailableWhenAnyAccountIsEnabled() {
        let enabledAccount = MailAccount(providerID: .gmail, email: "enabled@example.com")
        let disabledAccount = MailAccount(providerID: .gmail, email: "disabled@example.com", isEnabled: false)
        let supervisor = SupervisorFixture.makeSupervisor(accounts: [disabledAccount, enabledAccount])

        XCTAssertTrue(AccountPresentation.canRefresh(supervisor.accountStates))
    }

    @MainActor
    func testManualRefreshReportsSignInRequiredWhenSessionIsMissing() {
        let (supervisor, _) = SupervisorFixture.makeSupervisor(monitorFactory: { account, _, includeSpam in
            SpyMonitor(account: account, hasSession: false, includeSpam: includeSpam)
        })

        XCTAssertEqual(supervisor.refreshNow(), .signInRequired)
        XCTAssertEqual(supervisor.accountStates.first?.status, .reauthRequired)
    }

    @MainActor
    func testAccountSaveFailureDoesNotApplyEnabledStateChange() throws {
        let account = MailAccount(providerID: .gmail, email: "test@example.com")
        let suiteName = "mailbell.AccountSupervisorTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        try AccountStore(userDefaults: defaults).saveAccounts([account])
        let failingStore = AccountStore(
            userDefaults: defaults,
            saveData: { _, _ in throw AccountStore.AccountStoreError.saveFailed("disk full") }
        )
        let supervisor = AccountSupervisor(
            accountStore: failingStore,
            emailStore: EmailStore(persistence: EmailStorePersistence(userDefaults: defaults)),
            monitorFactory: { account, _, includeSpam in
                SpyMonitor(account: account, hasSession: false, includeSpam: includeSpam)
            }
        )

        supervisor.setEnabled(false, accountID: account.id)

        let state = try XCTUnwrap(supervisor.accountStates.first)
        XCTAssertTrue(state.account.isEnabled)
        XCTAssertEqual(state.lastError, "Could not save accounts: disk full")
    }

    @MainActor
    func testMenuIconIsFilledOnlyWhenEmailStoreHasItems() async throws {
        let (supervisor, account) = SupervisorFixture.makeSupervisor()

        XCTAssertEqual(supervisor.menuBarIconSystemImage, "bell")

        let didAdmit = await SupervisorFixture.admit(
            SupervisorFixture.makeHeader(gmMessageId: "icon"),
            into: supervisor,
            account: account
        )
        XCTAssertTrue(didAdmit)
        XCTAssertEqual(supervisor.menuBarIconSystemImage, "bell.fill")

        let item = try XCTUnwrap(supervisor.emailStoreItems.first)
        supervisor.dismissEmail(id: item.id)

        XCTAssertEqual(supervisor.menuBarIconSystemImage, "bell")
    }
}
