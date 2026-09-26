@testable import Mailbell
import XCTest

@MainActor
final class SettingsPresentationTests: XCTestCase {
    // MARK: - System Settings destinations (#31)

    func testSystemSettingsLabelsPromiseOnlyWhatTheButtonDoes() {
        // SystemSettings.open launches the app; macOS decides which pane shows.
        let label = SettingsCopy.Notifications.openSystemSettings
        XCTAssertEqual(label, "Open System Settings\u{2026}")
        XCTAssertFalse(label.contains("Notification Settings"), label)
    }

    func testTheLoginItemsLabelNamesThePaneTheAPIOpens() {
        // SMAppService.openSystemSettingsLoginItems() opens Login Items itself,
        // and a plain open takes no ellipsis (#61).
        XCTAssertEqual(SettingsCopy.Startup.openLoginItemsSettings, "Open Login Items Settings")
    }

    func testTheRouteToEachPreferenceIsStatedAsGuidance() {
        XCTAssertTrue(SettingsCopy.Startup.requiresApprovalExplanation.contains("Login Items"))
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
