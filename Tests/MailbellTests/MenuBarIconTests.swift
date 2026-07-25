@testable import mailbell
import XCTest

final class MenuBarIconTests: XCTestCase {
    func testAttentionOutranksPendingMail() {
        XCTAssertEqual(
            MenuBarIcon.systemImage(needsAttention: true, hasPendingItems: true),
            MenuBarIcon.attention
        )
        XCTAssertEqual(
            MenuBarIcon.systemImage(needsAttention: true, hasPendingItems: false),
            MenuBarIcon.attention
        )
    }

    func testBellReflectsPendingMailWhenNothingNeedsAttention() {
        XCTAssertEqual(
            MenuBarIcon.systemImage(needsAttention: false, hasPendingItems: true),
            MenuBarIcon.pending
        )
        XCTAssertEqual(
            MenuBarIcon.systemImage(needsAttention: false, hasPendingItems: false),
            MenuBarIcon.idle
        )
    }

    func testAttentionIsNotTheOrdinaryBell() {
        XCTAssertNotEqual(MenuBarIcon.attention, MenuBarIcon.idle)
        XCTAssertNotEqual(MenuBarIcon.attention, MenuBarIcon.pending)
    }

    func testOnlyUnrecoverableStatusesNeedAttention() {
        XCTAssertTrue(MonitorStatus.reauthRequired.needsAttention)
        XCTAssertTrue(MonitorStatus.error.needsAttention)
        XCTAssertFalse(MonitorStatus.connected.needsAttention)
        XCTAssertFalse(MonitorStatus.connecting.needsAttention)
        XCTAssertFalse(MonitorStatus.reconnecting.needsAttention)
        XCTAssertFalse(MonitorStatus.signedOut.needsAttention)
    }

    func testAccessibilityLabelAnnouncesSignInInsteadOfACount() {
        XCTAssertEqual(
            PendingCopy.menuBarAccessibilityLabel(count: 3, showsCount: true, needsAttention: true),
            "Mailbell, sign in needed"
        )
        XCTAssertEqual(
            PendingCopy.menuBarAccessibilityLabel(count: 3, showsCount: true, needsAttention: false),
            "Mailbell, 3 messages awaiting review"
        )
    }

    @MainActor
    func testSupervisorRaisesTheAlertIconWhenAnEnabledAccountNeedsSignIn() throws {
        let account = MailAccount(providerID: .gmail, email: "alert@example.com")
        let suiteName = "mailbell.MenuBarIconTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let store = AccountStore(userDefaults: defaults)
        try store.saveAccounts([account])
        let supervisor = AccountSupervisor(
            configProvider: {
                OAuthConfig(clientID: "dummy.apps.googleusercontent.com", clientSecret: nil)
            },
            accountStore: store,
            emailStore: EmailStore(persistence: EmailStorePersistence(userDefaults: defaults)),
            monitorFactory: { account, _, includeSpam in
                MenuBarIconSpyMonitor(account: account, includeSpam: includeSpam)
            },
            emailReadMarker: { _, _, _ in }
        )

        XCTAssertFalse(supervisor.needsAttention)
        XCTAssertEqual(supervisor.menuBarIconSystemImage, MenuBarIcon.idle)

        supervisor.statuses[account.id] = .reauthRequired
        XCTAssertTrue(supervisor.needsAttention)
        XCTAssertEqual(supervisor.menuBarIconSystemImage, MenuBarIcon.attention)

        supervisor.setEnabled(false, accountID: account.id)
        XCTAssertFalse(supervisor.needsAttention, "a disabled account is not an alert")
        XCTAssertEqual(supervisor.menuBarIconSystemImage, MenuBarIcon.idle)
    }
}

private final class MenuBarIconSpyMonitor: AccountMonitoring {
    weak var delegate: MailMonitorDelegate?
    private(set) var account: MailAccount
    let hasSession = false
    private(set) var includeSpam: Bool

    init(account: MailAccount, includeSpam: Bool) {
        self.account = account
        self.includeSpam = includeSpam
    }

    func updateAccount(_ account: MailAccount) {
        self.account = account
    }

    func hasStoredSession() throws -> Bool {
        false
    }

    func start() {}

    func stop(clearSession _: Bool) {}

    func forceReconnect() {}

    func refreshNow() {}

    func setIncludeSpam(_ includeSpam: Bool) {
        self.includeSpam = includeSpam
    }
}
