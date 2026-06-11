@testable import mailbell
import UserNotifications
import XCTest

final class NotificationAuthorizationStateTests: XCTestCase {
    func testUnbundledStateCannotPostAlerts() {
        XCTAssertFalse(NotificationAuthorizationState.unbundled.canPostAlert)
        XCTAssertEqual(NotificationAuthorizationState.unbundled.summary, "Unavailable outside app bundle")
        XCTAssertFalse(NotificationAuthorizationState.unbundled.canRequestPermission)
        XCTAssertFalse(NotificationAuthorizationState.unbundled.shouldOpenSystemSettings)
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
        XCTAssertFalse(state.canRequestPermission)
        XCTAssertTrue(state.shouldOpenSystemSettings)
    }

    func testNotDeterminedBundledStateCanRequestPermission() {
        let state = NotificationAuthorizationState(
            isBundled: true,
            status: .notDetermined,
            alertSetting: .notSupported,
            soundSetting: .notSupported,
            badgeSetting: .notSupported
        )

        XCTAssertFalse(state.canPostAlert)
        XCTAssertTrue(state.canRequestPermission)
        XCTAssertFalse(state.shouldOpenSystemSettings)
        XCTAssertEqual(state.detail, "Notification permission has not been requested yet.")
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
        XCTAssertTrue(state.shouldOpenSystemSettings)
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
        XCTAssertFalse(state.shouldOpenSystemSettings)
    }
}
