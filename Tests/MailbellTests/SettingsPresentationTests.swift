@testable import mailbell
import XCTest

final class SettingsPresentationTests: XCTestCase {
    func testSettingsTabsExposeRequiredNativeTopLevelSections() {
        XCTAssertEqual(
            SettingsTab.allCases.map(\.title),
            ["General", "Notifications", "Accounts", "Advanced", "About"]
        )
    }
}
