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
    func testManualRefreshReportsNoEnabledAccounts() {
        let disabledAccount = MailAccount(providerID: .gmail, email: "test@example.com", isEnabled: false)
        let (supervisor, _) = makeSupervisor(account: disabledAccount)

        XCTAssertEqual(supervisor.refreshNow(), .noEnabledAccounts)
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
        }
    ) -> (AccountSupervisor, MailAccount) {
        let suiteName = "mailbell.AccountSupervisorTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = AccountStore(userDefaults: defaults)
        store.saveAccounts([account])
        let supervisor = AccountSupervisor(
            configProvider: configProvider,
            accountStore: store,
            monitorFactory: monitorFactory
        )
        return (supervisor, account)
    }

    private func makeHeader() -> MessageHeader {
        MessageHeader(uid: 1, from: "sender@example.com", subject: "Subject", date: "", gmThreadId: nil)
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
