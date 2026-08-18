@testable import mailbell
import XCTest

final class AppSettingsStoreDefaultsTests: XCTestCase {
    func testUnsetPreferencesUseTheCentralizedDefaults() {
        let store = AppSettingsStore(userDefaults: makeDefaults())

        XCTAssertEqual(store.showPendingCount, AppSettingsStore.Defaults.showPendingCount)
        XCTAssertEqual(store.includeSpam, AppSettingsStore.Defaults.includeSpam)
        XCTAssertEqual(store.playNotificationSounds, AppSettingsStore.Defaults.playNotificationSounds)
    }

    func testRestoreDefaultsResetsEveryConfigurablePreference() {
        let defaults = makeDefaults()
        let store = AppSettingsStore(userDefaults: defaults)

        store.showPendingCount = !AppSettingsStore.Defaults.showPendingCount
        store.includeSpam = !AppSettingsStore.Defaults.includeSpam
        store.playNotificationSounds = !AppSettingsStore.Defaults.playNotificationSounds
        XCTAssertNotEqual(store.showPendingCount, AppSettingsStore.Defaults.showPendingCount)
        XCTAssertNotEqual(store.includeSpam, AppSettingsStore.Defaults.includeSpam)
        XCTAssertNotEqual(store.playNotificationSounds, AppSettingsStore.Defaults.playNotificationSounds)

        store.restoreDefaults()

        XCTAssertEqual(store.showPendingCount, AppSettingsStore.Defaults.showPendingCount)
        XCTAssertEqual(store.includeSpam, AppSettingsStore.Defaults.includeSpam)
        XCTAssertEqual(store.playNotificationSounds, AppSettingsStore.Defaults.playNotificationSounds)
        for key in AppSettingsStore.Key.configurable {
            XCTAssertNil(defaults.object(forKey: key), "\(key) must be cleared, not rewritten")
        }
    }

    func testRestoreDefaultsLeavesNonPreferenceStateAlone() {
        let defaults = makeDefaults()
        let store = AppSettingsStore(userDefaults: defaults)
        let account = MailAccount(providerID: .gmail, email: "keep@example.com")
        let accountStore = AccountStore(userDefaults: defaults)
        XCTAssertNoThrow(try accountStore.saveAccounts([account]))
        defaults.set(Data("handled".utf8), forKey: EmailStorePersistence.recordsKey)

        store.restoreDefaults()

        XCTAssertEqual(try accountStore.loadAccounts().map(\.email), ["keep@example.com"])
        XCTAssertNotNil(defaults.data(forKey: EmailStorePersistence.recordsKey))
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "mailbell.AppSettingsStoreDefaultsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
