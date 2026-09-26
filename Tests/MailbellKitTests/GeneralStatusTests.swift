import XCTest

@testable import MailbellKit

/// The app card's one-line status in Settings › General (#68).
final class GeneralStatusTests: XCTestCase {
    func testNoAccountPointsToAccounts() {
        XCTAssertEqual(
            GeneralStatus.text(accounts: [], conversationsToReview: 0, notificationsDenied: false),
            "No Gmail account. Add one in Accounts."
        )
    }

    func testAllConnectedSummarizesWatchingAndReview() {
        let accounts = [state("a@example.com", .connected), state("b@example.com", .connected)]

        XCTAssertEqual(
            GeneralStatus.text(accounts: accounts, conversationsToReview: 12, notificationsDenied: false),
            "Watching 2 accounts. 12 conversations to review."
        )
        XCTAssertEqual(
            GeneralStatus.text(accounts: [accounts[0]], conversationsToReview: 0, notificationsDenied: false),
            "Watching 1 account. Nothing to review."
        )
        XCTAssertEqual(
            GeneralStatus.text(accounts: [accounts[0]], conversationsToReview: 1, notificationsDenied: false),
            "Watching 1 account. 1 conversation to review."
        )
    }

    func testAnAccountNeedingSignInIsNamed() {
        let accounts = [state("a@example.com", .connected), state("you@gmail.com", .signInRequired)]

        XCTAssertEqual(
            GeneralStatus.text(accounts: accounts, conversationsToReview: 3, notificationsDenied: true),
            "you@gmail.com needs sign-in."
        )
        XCTAssertEqual(
            GeneralStatus.text(
                accounts: [state("a@example.com", .signInRequired), state("b@example.com", .signInRequired)],
                conversationsToReview: 0,
                notificationsDenied: false
            ),
            "2 accounts need sign-in."
        )
    }

    func testAConnectionErrorIsNamed() {
        XCTAssertEqual(
            GeneralStatus.text(
                accounts: [state("you@gmail.com", .error)],
                conversationsToReview: 0,
                notificationsDenied: true
            ),
            "Can't connect to you@gmail.com."
        )
    }

    func testSignInOutranksAConnectionError() {
        let accounts = [state("broken@example.com", .error), state("expired@example.com", .signInRequired)]

        XCTAssertEqual(
            GeneralStatus.text(accounts: accounts, conversationsToReview: 0, notificationsDenied: false),
            "expired@example.com needs sign-in."
        )
    }

    func testDeniedNotificationsFollowAccountProblems() {
        XCTAssertEqual(
            GeneralStatus.text(
                accounts: [state("a@example.com", .connected)],
                conversationsToReview: 4,
                notificationsDenied: true
            ),
            "Notifications are off in System Settings."
        )
    }

    func testPausedAccountsAreNotProblems() {
        let paused = [
            state("a@example.com", .signInRequired, isEnabled: false),
            state("b@example.com", .error, isEnabled: false),
        ]

        XCTAssertEqual(
            GeneralStatus.text(accounts: paused, conversationsToReview: 0, notificationsDenied: false),
            "Paused. No account is being watched."
        )
        XCTAssertEqual(
            GeneralStatus.text(
                accounts: paused + [state("c@example.com", .connected)],
                conversationsToReview: 2,
                notificationsDenied: false
            ),
            "Watching 1 account. 2 conversations to review."
        )
    }

    private func state(
        _ email: String,
        _ status: MonitorStatus,
        isEnabled: Bool = true
    ) -> AccountRuntimeState {
        AccountRuntimeState(
            account: MailAccount(providerID: .gmail, email: email, isEnabled: isEnabled),
            status: status
        )
    }
}
