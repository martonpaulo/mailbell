@testable import mailbell
import XCTest

final class AccountPresentationTests: XCTestCase {
    // MARK: - Retained window disclosure (#27)

    func testOverflowNoticeAppearsOnlyWhenConversationsAreHidden() {
        XCTAssertNil(PendingCopy.overflowNotice(hiddenConversations: 0))
        XCTAssertEqual(
            PendingCopy.overflowNotice(hiddenConversations: 1),
            "1 more conversation awaiting review. Open Gmail to see the rest."
        )
        XCTAssertEqual(
            PendingCopy.overflowNotice(hiddenConversations: 12),
            "12 more conversations awaiting review. Open Gmail to see the rest."
        )
    }

    func testOverflowNoticeDoesNotInventATotalForGmail() {
        // Mailbell has no bounded way to know how much mail is left in Gmail,
        // so the notice must speak only about what it retains.
        let notice = PendingCopy.overflowNotice(hiddenConversations: 12) ?? ""

        XCTAssertFalse(notice.lowercased().contains("total"))
        XCTAssertTrue(notice.contains("Open Gmail"), "the notice carries its recovery action")
    }

    func testBulkActionScopeNamesEveryRetainedMessage() {
        XCTAssertEqual(PendingCopy.bulkActionScope(retainedMessages: 1), "Applies to 1 retained message")
        XCTAssertEqual(PendingCopy.bulkActionScope(retainedMessages: 240), "Applies to 240 retained messages")
    }

    // MARK: - Menu bar accessibility label (#30)

    func testTheLabelSaysSignInOnlyWhenSigningInIsTheRemedy() {
        XCTAssertEqual(
            PendingCopy.menuBarAccessibilityLabel(count: 0, needsAttention: true, needsSignIn: true),
            "Mailbell, sign in needed"
        )
    }

    func testAGenericAccountErrorDoesNotPrescribeSigningIn() {
        // MonitorStatus.error also needs attention, but Reconnect is its remedy.
        let label = PendingCopy.menuBarAccessibilityLabel(count: 0, needsAttention: true, needsSignIn: false)

        XCTAssertEqual(label, "Mailbell, account needs attention")
        XCTAssertFalse(label.lowercased().contains("sign in"))
    }

    func testAttentionStillOutranksTheReviewCount() {
        XCTAssertEqual(
            PendingCopy.menuBarAccessibilityLabel(count: 5, needsAttention: true, needsSignIn: false),
            "Mailbell, account needs attention"
        )
    }

    func testOnlyReauthRequiredCountsAsNeedingSignIn() {
        XCTAssertTrue(MonitorStatus.reauthRequired.needsSignIn)
        XCTAssertFalse(MonitorStatus.error.needsSignIn)
        XCTAssertTrue(MonitorStatus.error.needsAttention, "still attention, just not sign-in")
        XCTAssertFalse(MonitorStatus.connected.needsSignIn)
        XCTAssertFalse(MonitorStatus.signedOut.needsSignIn)
    }

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

    func testAccountMenuIconReflectsStatus() {
        XCTAssertEqual(
            AccountPresentation.menuIconSystemName(for: state(status: .connected)),
            "checkmark.circle.fill"
        )
        XCTAssertEqual(
            AccountPresentation.menuIconSystemName(for: state(status: .connecting)),
            "arrow.clockwise.circle"
        )
        XCTAssertEqual(
            AccountPresentation.menuIconSystemName(for: state(status: .reconnecting)),
            "arrow.clockwise.circle"
        )
        XCTAssertEqual(
            AccountPresentation.menuIconSystemName(for: state(status: .reauthRequired)),
            "exclamationmark.triangle.fill"
        )
        XCTAssertEqual(
            AccountPresentation.menuIconSystemName(for: state(status: .signedOut, isEnabled: false)),
            "pause.circle"
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
