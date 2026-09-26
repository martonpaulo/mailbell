@testable import MailbellKit
import MailbellTestSupport
import XCTest

@MainActor
final class AppSettingsStoreDefaultsTests: XCTestCase {
    func testUnsetPreferencesUseTheCentralizedDefaults() {
        let store = AppSettingsStore(userDefaults: makeDefaults())

        XCTAssertEqual(store.showsMenuBarCount, AppSettingsStore.Defaults.showsMenuBarCount)
        XCTAssertEqual(store.includeSpam, AppSettingsStore.Defaults.includeSpam)
        XCTAssertEqual(store.playNotificationSounds, AppSettingsStore.Defaults.playNotificationSounds)
    }

    func testRestoreDefaultsResetsEveryConfigurablePreference() {
        let defaults = makeDefaults()
        let store = AppSettingsStore(userDefaults: defaults)

        store.showsMenuBarCount = !AppSettingsStore.Defaults.showsMenuBarCount
        store.includeSpam = !AppSettingsStore.Defaults.includeSpam
        store.playNotificationSounds = !AppSettingsStore.Defaults.playNotificationSounds
        XCTAssertNotEqual(store.showsMenuBarCount, AppSettingsStore.Defaults.showsMenuBarCount)
        XCTAssertNotEqual(store.includeSpam, AppSettingsStore.Defaults.includeSpam)
        XCTAssertNotEqual(store.playNotificationSounds, AppSettingsStore.Defaults.playNotificationSounds)

        store.restoreDefaults()

        XCTAssertEqual(store.showsMenuBarCount, AppSettingsStore.Defaults.showsMenuBarCount)
        XCTAssertEqual(store.includeSpam, AppSettingsStore.Defaults.includeSpam)
        XCTAssertEqual(store.playNotificationSounds, AppSettingsStore.Defaults.playNotificationSounds)
        for key in StorageKeys.settingsConfigurable {
            XCTAssertNil(defaults.object(forKey: key), "\(key) must be cleared, not rewritten")
        }
    }

    func testRestoreDefaultsLeavesNonPreferenceStateAlone() {
        let defaults = makeDefaults()
        let store = AppSettingsStore(userDefaults: defaults)
        let account = MailAccount(providerID: .gmail, email: "keep@example.com")
        let accountStore = AccountStore(userDefaults: defaults)
        XCTAssertNoThrow(try accountStore.saveAccounts([account]))
        defaults.set(Data("handled".utf8), forKey: StorageKeys.handledRecords)

        store.restoreDefaults()

        XCTAssertEqual(try accountStore.loadAccounts().map(\.email), ["keep@example.com"])
        XCTAssertNotNil(defaults.data(forKey: StorageKeys.handledRecords))
    }

    private func makeDefaults() -> UserDefaults {
        let defaults = TestDefaults.make()
        return defaults
    }
}
