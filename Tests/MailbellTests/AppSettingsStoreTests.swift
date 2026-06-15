@testable import mailbell
import XCTest

final class AppSettingsStoreTests: XCTestCase {
    func testDefaultsPreserveCurrentBehavior() {
        let store = AppSettingsStore(userDefaults: makeDefaults())

        XCTAssertTrue(store.showPendingCount)
        XCTAssertFalse(store.includeSpam)
    }

    func testPersistsSettings() {
        let defaults = makeDefaults()
        let store = AppSettingsStore(userDefaults: defaults)

        store.showPendingCount = false
        store.includeSpam = true

        let reloaded = AppSettingsStore(userDefaults: defaults)
        XCTAssertFalse(reloaded.showPendingCount)
        XCTAssertTrue(reloaded.includeSpam)
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "mailbell.AppSettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
