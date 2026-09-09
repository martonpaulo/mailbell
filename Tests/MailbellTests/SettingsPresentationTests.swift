@testable import mailbell
import XCTest

final class SettingsPresentationTests: XCTestCase {
    // MARK: - System Settings destinations (#31)

    func testSystemSettingsLabelsPromiseOnlyWhatTheButtonDoes() {
        // SystemSettings.open launches the app; macOS decides which pane shows.
        for label in [
            SettingsCopy.Startup.openLoginItemsSettings,
            SettingsCopy.Notifications.openSystemSettings
        ] {
            XCTAssertEqual(label, "Open System Settings\u{2026}")
            XCTAssertFalse(label.contains("Login Items"), label)
            XCTAssertFalse(label.contains("Notification Settings"), label)
            XCTAssertTrue(label.hasSuffix("\u{2026}"), "opening another app takes an ellipsis: \(label)")
        }
    }

    func testTheRouteToEachPreferenceIsStatedAsGuidance() {
        XCTAssertTrue(SettingsCopy.Startup.loginItemsRoute.contains("Login Items"))
        XCTAssertTrue(SettingsCopy.Notifications.notificationsRoute.contains("Notifications"))
    }

    func testTheNotificationsFooterAddsTheRouteOnlyWhenItIsNeeded() {
        let withRoute = SettingsCopy.Notifications.footer(
            isSendingTest: false,
            testMessage: nil,
            statusMessage: nil,
            needsSystemSettings: true
        )
        let withoutRoute = SettingsCopy.Notifications.footer(
            isSendingTest: false,
            testMessage: nil,
            statusMessage: nil,
            needsSystemSettings: false
        )

        XCTAssertTrue(withRoute.contains(SettingsCopy.Notifications.notificationsRoute))
        XCTAssertFalse(withoutRoute.contains(SettingsCopy.Notifications.notificationsRoute))
    }

    func testSettingsTabsExposeRequiredNativeTopLevelSections() {
        XCTAssertEqual(
            SettingsTab.allCases.map(\.title),
            ["General", "Notifications", "Accounts", "About"]
        )
    }
}
