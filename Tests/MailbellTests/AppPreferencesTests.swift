@testable import mailbell
import XCTest

final class AppPreferencesTests: XCTestCase {
    func testMenuBarIconPreferenceDefaultsToVisible() {
        let defaults = makeDefaults()

        XCTAssertTrue(AppPreferences.showMenuBarIcon(userDefaults: defaults))
    }

    func testMenuBarIconPreferencePersists() {
        let defaults = makeDefaults()

        AppPreferences.setShowMenuBarIcon(false, userDefaults: defaults)
        XCTAssertFalse(AppPreferences.showMenuBarIcon(userDefaults: defaults))

        AppPreferences.setShowMenuBarIcon(true, userDefaults: defaults)
        XCTAssertTrue(AppPreferences.showMenuBarIcon(userDefaults: defaults))
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "mailbell.AppPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
