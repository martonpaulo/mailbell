@testable import mailbell
import UserNotifications
import XCTest

final class NotificationAuthorizationStateTests: XCTestCase {
    func testUnbundledStateCannotPostAlerts() {
        XCTAssertFalse(NotificationAuthorizationState.unbundled.canPostAlert)
        XCTAssertEqual(NotificationAuthorizationState.unbundled.summary, "Unavailable outside app bundle")
    }

    func testDeniedStateCannotPostAlerts() {
        let state = NotificationAuthorizationState(
            isBundled: true,
            status: .denied,
            alertSetting: .enabled,
            soundSetting: .enabled,
            badgeSetting: .enabled
        )

        XCTAssertFalse(state.canPostAlert)
        XCTAssertEqual(state.summary, "Denied")
    }

    func testAuthorizedStateRequiresAlerts() {
        let state = NotificationAuthorizationState(
            isBundled: true,
            status: .authorized,
            alertSetting: .disabled,
            soundSetting: .enabled,
            badgeSetting: .enabled
        )

        XCTAssertFalse(state.canPostAlert)
        XCTAssertEqual(state.detail, "Notification alerts are disabled for Mailbell.")
    }

    func testAuthorizedStateCanPostAlerts() {
        let state = NotificationAuthorizationState(
            isBundled: true,
            status: .authorized,
            alertSetting: .enabled,
            soundSetting: .disabled,
            badgeSetting: .enabled
        )

        XCTAssertTrue(state.canPostAlert)
        XCTAssertEqual(state.summary, "Allowed")
    }
}
