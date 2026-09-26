import MailbellTestSupport
import XCTest

@testable import Mailbell
@testable import MailbellKit

@MainActor
final class LegacyDomainMigrationTests: XCTestCase {
    private let accountID = "7F2C1B64-0C4B-4F0E-9D55-3E0B8C9A1D2E"

    private var checkpointKey: String {
        "mailbell.account.\(accountID).mailbox.INBOX.lastSeenUID"
    }

    private var legacyDomain: [String: Any] {
        [
            "mailbell.accounts": Data([1, 2, 3]),
            checkpointKey: 42,
            StorageKeys.includeSpam: true,
            StorageKeys.showsMenuBarCount: false,
            StorageKeys.systemSettingsWindowFrame: "0 0 720 560",
            "NSStatusItem Preferred Position Item-0": 310,
            "SUAutomaticallyUpdate": true,
            "SULastCheckTime": Date(timeIntervalSince1970: 0),
            "SUUpdateGroupIdentifier": 7,
            "AppleLanguages": ["en"],
        ]
    }

    func testCopiesOwnedNamesAndSkipsOthers() throws {
        let values = try XCTUnwrap(
            LegacyDomainMigration.valuesToCopy(legacyDomain: legacyDomain, currentDomain: [:])
        )

        XCTAssertEqual(
            Set(values.keys),
            [
                "mailbell.accounts",
                checkpointKey,
                StorageKeys.includeSpam,
                StorageKeys.showsMenuBarCount,
                StorageKeys.systemSettingsWindowFrame,
                "NSStatusItem Preferred Position Item-0",
                "SUAutomaticallyUpdate",
                StorageKeys.legacyDomainCopied,
            ]
        )
        XCTAssertEqual(values[checkpointKey] as? Int, 42)
    }

    func testNeverOverwritesAValueTheCurrentDomainStores() throws {
        let values = try XCTUnwrap(
            LegacyDomainMigration.valuesToCopy(
                legacyDomain: legacyDomain,
                currentDomain: [StorageKeys.includeSpam: false]
            )
        )

        XCTAssertNil(values[StorageKeys.includeSpam])
        XCTAssertEqual(values[StorageKeys.showsMenuBarCount] as? Bool, false)
    }

    func testCopiesNothingOnceTheMarkerExists() {
        XCTAssertNil(
            LegacyDomainMigration.valuesToCopy(
                legacyDomain: legacyDomain,
                currentDomain: [StorageKeys.legacyDomainCopied: true]
            )
        )
    }

    func testWritesOnlyTheMarkerWithoutALegacyDomain() {
        for legacy in [nil, [:]] as [[String: Any]?] {
            let values = LegacyDomainMigration.valuesToCopy(legacyDomain: legacy, currentDomain: [:])
            XCTAssertEqual(values?.keys.sorted(), [StorageKeys.legacyDomainCopied])
        }
    }

    func testMigrateCopiesTheOldDomainOnce() throws {
        let legacy = TestDefaults()
        for (name, value) in legacyDomain {
            legacy.defaults.set(value, forKey: name)
        }
        let current = TestDefaults()

        LegacyDomainMigration.migrate(
            current.defaults,
            currentDomain: current.persistentDomain ?? [:],
            legacyDomain: legacy.persistentDomain
        )

        XCTAssertEqual(current.defaults.data(forKey: "mailbell.accounts"), Data([1, 2, 3]))
        XCTAssertEqual(current.defaults.integer(forKey: checkpointKey), 42)
        XCTAssertTrue(AppSettingsStore(userDefaults: current.defaults).includeSpam)
        XCTAssertNil(current.defaults.object(forKey: "SULastCheckTime"))
        XCTAssertTrue(current.defaults.bool(forKey: StorageKeys.legacyDomainCopied))

        legacy.defaults.set(99, forKey: checkpointKey)
        legacy.defaults.set(false, forKey: StorageKeys.includeSpam)
        LegacyDomainMigration.migrate(
            current.defaults,
            currentDomain: current.persistentDomain ?? [:],
            legacyDomain: legacy.persistentDomain
        )

        XCTAssertEqual(current.defaults.integer(forKey: checkpointKey), 42)
        XCTAssertTrue(AppSettingsStore(userDefaults: current.defaults).includeSpam)
    }

    func testRestoreDefaultsKeepsTheMarker() {
        let current = TestDefaults()
        LegacyDomainMigration.migrate(current.defaults, currentDomain: [:], legacyDomain: legacyDomain)

        AppSettingsStore(userDefaults: current.defaults).restoreDefaults()

        XCTAssertTrue(current.defaults.bool(forKey: StorageKeys.legacyDomainCopied))
    }
}
