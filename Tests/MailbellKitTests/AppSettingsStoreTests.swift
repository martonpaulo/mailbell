import MailbellTestSupport
import XCTest

@testable import MailbellKit

@MainActor
final class AppSettingsStoreTests: XCTestCase {
    func testDefaultsPreserveCurrentBehavior() {
        let store = AppSettingsStore(userDefaults: makeDefaults())

        XCTAssertTrue(store.showsMenuBarCount)
        XCTAssertFalse(store.includeSpam)
        XCTAssertTrue(store.playNotificationSounds)
    }

    func testPersistsSettings() {
        let defaults = makeDefaults()
        let store = AppSettingsStore(userDefaults: defaults)

        store.showsMenuBarCount = false
        store.includeSpam = true
        store.playNotificationSounds = false

        let reloaded = AppSettingsStore(userDefaults: defaults)
        XCTAssertFalse(reloaded.showsMenuBarCount)
        XCTAssertTrue(reloaded.includeSpam)
        XCTAssertFalse(reloaded.playNotificationSounds)
    }

    private func makeDefaults() -> UserDefaults {
        let defaults = TestDefaults.make()
        return defaults
    }
}
