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
        XCTAssertEqual(PendingCopy.menuSectionTitle, "Awaiting Review")
        XCTAssertEqual(PendingCopy.emptyMenuTitle, "No messages")
        XCTAssertEqual(PendingCopy.openActionTitle, "Open")
        XCTAssertEqual(PendingCopy.markAsReadActionTitle, "Mark as Read")
        XCTAssertEqual(PendingCopy.dismissActionTitle, "Dismiss")
        XCTAssertEqual(PendingCopy.reviewSectionTitle, "Awaiting Review")
        XCTAssertEqual(PendingCopy.reviewCountText(0), "No messages")
        XCTAssertEqual(PendingCopy.reviewCountText(1), "1 message")
        XCTAssertEqual(PendingCopy.reviewCountText(2), "2 messages")
        XCTAssertEqual(PendingCopy.menuBarAccessibilityLabel(count: 2), "Mailbell, 2 messages awaiting review")
        XCTAssertEqual(PendingCopy.menuBarAccessibilityLabel(count: 1), "Mailbell, 1 message awaiting review")
        XCTAssertEqual(PendingCopy.menuBarAccessibilityLabel(count: 2, showsCount: false), "Mailbell")
    }

    func testAccountStatusPresentation() {
        XCTAssertEqual(AccountPresentation.statusText(for: state(status: .connected)), "Connected")
        XCTAssertEqual(AccountPresentation.statusText(for: state(status: .reauthRequired)), "Sign in needed")
    }

    func testAccountMenuTitleCombinesStatusAndEmail() {
        XCTAssertEqual(
            AccountPresentation.menuTitle(for: state(email: "example@example.com", status: .connected)),
            "Connected • example@example.com"
        )
    }

    func testAccountDetailPresentationOmitsProviderPrefix() {
        XCTAssertEqual(
            AccountPresentation.detailText(for: state(status: .connected)),
            "Monitoring Inbox."
        )
        XCTAssertEqual(
            AccountPresentation.detailText(for: state(status: .connected), includeSpam: true),
            "Monitoring Inbox and Spam."
        )
        XCTAssertEqual(
            AccountPresentation.detailText(for: state(status: .reconnecting)),
            "Reconnecting."
        )
    }

    func testWebmailOpenLabelUsesOnlyAccountEmail() {
        XCTAssertEqual(
            AccountPresentation.webmailOpenLabel(email: "user@example.com"),
            "user@example.com"
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
