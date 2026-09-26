import XCTest

@testable import MailbellKit

@MainActor
final class AccountPresentationTests: XCTestCase {
    // MARK: - Retained window disclosure (#27)

    func testOverflowNoticeAppearsOnlyWhenConversationsAreHidden() {
        XCTAssertNil(MenuCopy.overflowNotice(hiddenConversations: 0))
        XCTAssertEqual(
            MenuCopy.overflowNotice(hiddenConversations: 1),
            "1 more conversation not shown. Open Gmail to see it."
        )
        XCTAssertEqual(
            MenuCopy.overflowNotice(hiddenConversations: 12),
            "12 more conversations not shown. Open Gmail to see them."
        )
    }

    func testOverflowNoticeDoesNotInventATotalForGmail() {
        // Mailbell has no bounded way to know how much mail is left in Gmail,
        // so the notice must speak only about what it retains.
        let notice = MenuCopy.overflowNotice(hiddenConversations: 12) ?? ""

        XCTAssertFalse(notice.lowercased().contains("total"))
        XCTAssertTrue(notice.contains("Open Gmail"), "the notice carries its recovery action")
    }

    func testBulkScopeNamesMessagesAndConversations() {
        XCTAssertEqual(MenuCopy.bulkScope(messages: 1, conversations: 1), "Includes 1 message in 1 conversation.")
        XCTAssertEqual(MenuCopy.bulkScope(messages: 4, conversations: 1), "Includes 4 messages in 1 conversation.")
        XCTAssertEqual(
            MenuCopy.bulkScope(messages: 37, conversations: 12),
            "Includes 37 messages in 12 conversations."
        )
    }

    // MARK: - Menu bar accessibility label (#30)

    func testTheLabelSaysSignInOnlyWhenSigningInIsTheRemedy() {
        XCTAssertEqual(
            MenuCopy.menuBarAccessibilityLabel(count: 0, needsAttention: true, needsSignIn: true),
            "Mailbell, sign-in needed"
        )
    }

    func testAGenericAccountErrorDoesNotPrescribeSigningIn() {
        // MonitorStatus.error also needs attention, but Reconnect is its remedy.
        let label = MenuCopy.menuBarAccessibilityLabel(count: 0, needsAttention: true, needsSignIn: false)

        XCTAssertEqual(label, "Mailbell, can't connect")
        XCTAssertFalse(label.lowercased().contains("sign"))
    }

    func testAttentionStillOutranksTheReviewCount() {
        XCTAssertEqual(
            MenuCopy.menuBarAccessibilityLabel(count: 5, needsAttention: true, needsSignIn: false),
            "Mailbell, can't connect"
        )
    }

    func testOnlySignInRequiredCountsAsNeedingSignIn() {
        XCTAssertTrue(MonitorStatus.signInRequired.needsSignIn)
        XCTAssertFalse(MonitorStatus.error.needsSignIn)
        XCTAssertTrue(MonitorStatus.error.needsAttention, "still attention, just not sign-in")
        XCTAssertFalse(MonitorStatus.connected.needsSignIn)
        XCTAssertFalse(MonitorStatus.signedOut.needsSignIn)
    }

    func testRecoveryActionMapping() {
        XCTAssertNil(AccountRecoveryAction.needed(for: state(status: .connected)))
        XCTAssertNil(AccountRecoveryAction.needed(for: state(status: .reconnecting)))
        XCTAssertEqual(AccountRecoveryAction.needed(for: state(status: .signInRequired)), .signInAgain)
        XCTAssertEqual(AccountRecoveryAction.needed(for: state(status: .error)), .reconnect)
        XCTAssertEqual(AccountRecoveryAction.needed(for: state(status: .signedOut)), .reconnect)
        XCTAssertEqual(AccountRecoveryAction.needed(for: state(status: .signedOut, isEnabled: false)), .enable)
    }

    func testRecoveryTitlesUseTheMenuTerms() {
        XCTAssertEqual(AccountRecoveryAction.enable.title, "Resume Watching")
        XCTAssertEqual(AccountRecoveryAction.reconnect.title, "Reconnect")
        XCTAssertEqual(AccountRecoveryAction.signInAgain.title, "Sign In Again…")
    }

    // MARK: - One counting unit (#69)

    func testTheMenuCountsConversations() {
        XCTAssertEqual(MenuCopy.menuSectionTitle, "To review")
        XCTAssertEqual(MenuCopy.toReview(0), "Nothing to review")
        XCTAssertEqual(MenuCopy.toReview(1), "1 conversation to review")
        XCTAssertEqual(MenuCopy.toReview(12), "12 conversations to review")
        XCTAssertEqual(MenuCopy.reviewCountText(0), "No conversations")
        XCTAssertEqual(MenuCopy.reviewCountText(1), "1 conversation")
        XCTAssertEqual(MenuCopy.reviewCountText(2), "2 conversations")
    }

    func testTheAccessibilityLabelUsesTheSameUnitAsTheMenu() {
        XCTAssertEqual(MenuCopy.menuBarAccessibilityLabel(count: 12), "Mailbell, 12 conversations to review")
        XCTAssertEqual(MenuCopy.menuBarAccessibilityLabel(count: 1), "Mailbell, 1 conversation to review")
        XCTAssertEqual(MenuCopy.menuBarAccessibilityLabel(count: 2, showsCount: false), "Mailbell")
        XCTAssertEqual(MenuCopy.menuBarAccessibilityLabel(count: 0), "Mailbell")
    }

    func testActionLabelsSayWhereTheyAct() {
        XCTAssertEqual(MenuCopy.openInGmail, "Open in Gmail")
        XCTAssertEqual(MenuCopy.markAsRead, "Mark as Read in Gmail")
        XCTAssertEqual(MenuCopy.dismiss, "Dismiss (Keep Unread in Gmail)")
        XCTAssertEqual(MenuCopy.dismissAll, "Dismiss All (Keep Unread in Gmail)")
        XCTAssertEqual(MenuCopy.checkForNewMail, "Check for New Mail")
    }

    func testBulkResultsCountMessages() {
        XCTAssertEqual(MenuCopy.BulkResult.marked(messages: 10), "Marked 10 messages as read in Gmail.")
        XCTAssertEqual(
            MenuCopy.BulkResult.partiallyMarked(marked: 10, failed: 2),
            "Marked 10 messages as read in Gmail. 2 couldn't be updated. Try again."
        )
        XCTAssertEqual(MenuCopy.BulkResult.dismissed(messages: 12), "Dismissed 12 messages. They stay unread in Gmail.")
        XCTAssertEqual(MenuCopy.BulkResult.dismissed(messages: 1), "Dismissed 1 message. It stays unread in Gmail.")
    }

    // MARK: - Account list row (#68)

    func testEachStatusReadsAsOneShortPhrase() {
        XCTAssertEqual(AccountPresentation.statusText(for: state(status: .connected, isEnabled: false)), "Paused")
        XCTAssertEqual(AccountPresentation.statusText(for: state(status: .connecting)), "Connecting…")
        XCTAssertEqual(AccountPresentation.statusText(for: state(status: .connected)), "Watching Inbox")
        XCTAssertEqual(
            AccountPresentation.statusText(for: state(status: .connected), includeSpam: true),
            "Watching Inbox and Spam"
        )
        XCTAssertEqual(AccountPresentation.statusText(for: state(status: .reconnecting)), "Reconnecting…")
        XCTAssertEqual(AccountPresentation.statusText(for: state(status: .signInRequired)), "Sign-in needed")
        XCTAssertEqual(AccountPresentation.statusText(for: state(status: .error)), "Can't connect")
        XCTAssertEqual(AccountPresentation.statusText(for: state(status: .signedOut)), "Not connected")
    }

    func testTheStatusDotFollowsTheStatus() {
        XCTAssertEqual(AccountPresentation.statusLevel(for: state(status: .connected)), .active)
        XCTAssertEqual(AccountPresentation.statusLevel(for: state(status: .connecting)), .progress)
        XCTAssertEqual(AccountPresentation.statusLevel(for: state(status: .reconnecting)), .progress)
        XCTAssertEqual(AccountPresentation.statusLevel(for: state(status: .signInRequired)), .warning)
        XCTAssertEqual(AccountPresentation.statusLevel(for: state(status: .error)), .error)
        XCTAssertEqual(AccountPresentation.statusLevel(for: state(status: .signedOut)), .inactive)
        // A paused account is a choice, never shown as a problem.
        XCTAssertEqual(AccountPresentation.statusLevel(for: state(status: .error, isEnabled: false)), .inactive)
    }

    func testTheOverviewCountsAccountsAndThoseNeedingSignIn() {
        XCTAssertEqual(AccountPresentation.overview([]), "No Gmail account")
        XCTAssertEqual(AccountPresentation.overview([state(status: .connected)]), "1 account")
        XCTAssertEqual(
            AccountPresentation.overview([state(status: .connected), state(status: .signInRequired)]),
            "2 accounts (1 needs sign-in)"
        )
        XCTAssertEqual(
            AccountPresentation.overview([
                state(status: .signInRequired), state(status: .signInRequired),
                state(status: .signInRequired, isEnabled: false),
            ]),
            "3 accounts (2 need sign-in)"
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
            AccountPresentation.menuIconSystemName(for: state(status: .signInRequired)),
            "exclamationmark.triangle.fill"
        )
        XCTAssertEqual(
            AccountPresentation.menuIconSystemName(for: state(status: .signedOut, isEnabled: false)),
            "pause.circle"
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
