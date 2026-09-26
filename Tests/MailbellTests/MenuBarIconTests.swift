@testable import Mailbell
@testable import MailbellKit
import MailbellTestSupport
import XCTest

/// The supervisor half of the menu bar glyph; the pure precedence is in
/// MailbellKitTests (#80).
@MainActor
final class MenuBarIconTests: XCTestCase {
    @MainActor
    func testSupervisorRaisesTheAlertIconWhenAnEnabledAccountNeedsSignIn() throws {
        let account = MailAccount(providerID: .gmail, email: "alert@example.com")
        let defaults = TestDefaults.make()
        let store = AccountStore(userDefaults: defaults)
        try store.saveAccounts([account])
        let supervisor = AccountSupervisor(
            notifier: RecordingNotifier(),
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
