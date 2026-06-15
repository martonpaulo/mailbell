@testable import mailbell
import XCTest

final class AccountPresentationTests: XCTestCase {
    func testRecoveryActionMapping() {
        XCTAssertNil(AccountRecoveryAction.needed(for: state(status: .connected)))
        XCTAssertNil(AccountRecoveryAction.needed(for: state(status: .reconnecting)))
        XCTAssertEqual(AccountRecoveryAction.needed(for: state(status: .reauthRequired)), .signInAgain)
        XCTAssertEqual(AccountRecoveryAction.needed(for: state(status: .error)), .reconnect)
        XCTAssertEqual(AccountRecoveryAction.needed(for: state(status: .signedOut)), .reconnect)
        XCTAssertEqual(AccountRecoveryAction.needed(for: state(status: .signedOut, isEnabled: false)), .enable)
    }

    func testPendingCopyDoesNotClaimGmailUnreadState() {
        XCTAssertEqual(PendingCopy.menuSectionTitle, "Pending")
        XCTAssertEqual(PendingCopy.emptyMenuTitle, "No pending emails")
        XCTAssertEqual(PendingCopy.menuBarAccessibilityLabel(count: 2), "Mailbell, 2 pending emails")
    }

    func testSingleAndMultiAccountPresentationTitles() {
        let single = state(email: "one@example.com", status: .connected)
        let multi = state(email: "two@example.com", status: .reauthRequired)

        XCTAssertEqual(AccountPresentation.compactTitle(for: single), "Connected - one@example.com")
        XCTAssertEqual(
            AccountPresentation.multiAccountMenuTitle(for: multi, pendingCount: 3),
            "two@example.com - Sign in needed - 3 pending"
        )
    }

    private func state(
        email: String = "user@example.com",
        status: MonitorStatus,
        isEnabled: Bool = true
    ) -> AccountRuntimeState {
        AccountRuntimeState(
            account: MailAccount(providerID: .gmail, email: email, isEnabled: isEnabled),
            status: status,
            lastError: nil,
            webmailOpenError: nil
        )
    }
}
