@testable import MailbellKit
import XCTest

@MainActor
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
        XCTAssertTrue(MonitorStatus.signInRequired.needsAttention)
        XCTAssertTrue(MonitorStatus.error.needsAttention)
        XCTAssertFalse(MonitorStatus.connected.needsAttention)
        XCTAssertFalse(MonitorStatus.connecting.needsAttention)
        XCTAssertFalse(MonitorStatus.reconnecting.needsAttention)
        XCTAssertFalse(MonitorStatus.signedOut.needsAttention)
    }

    func testAccessibilityLabelAnnouncesAttentionInsteadOfACount() {
        XCTAssertEqual(
            MenuCopy.menuBarAccessibilityLabel(
                count: 3,
                showsCount: true,
                needsAttention: true,
                needsSignIn: true
            ),
            "Mailbell, sign in needed"
        )
        // Attention that is not an expired sign-in must not say "sign in".
        XCTAssertEqual(
            MenuCopy.menuBarAccessibilityLabel(count: 3, showsCount: true, needsAttention: true),
            "Mailbell, account needs attention"
        )
        XCTAssertEqual(
            MenuCopy.menuBarAccessibilityLabel(count: 3, showsCount: true, needsAttention: false),
            "Mailbell, 3 messages awaiting review"
        )
    }
}
