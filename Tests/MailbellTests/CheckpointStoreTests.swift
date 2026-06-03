@testable import mailbell
import XCTest

final class CheckpointStoreTests: XCTestCase {
    func testCheckpointsAreNamespacedByAccount() {
        let defaults = makeDefaults()
        var first = CheckpointStore(accountID: UUID(), userDefaults: defaults)
        let second = CheckpointStore(accountID: UUID(), userDefaults: defaults)

        first.storedUIDValidity = 10
        first.lastSeenUID = 42

        XCTAssertEqual(first.storedUIDValidity, 10)
        XCTAssertEqual(first.lastSeenUID, 42)
        XCTAssertEqual(second.storedUIDValidity, 0)
        XCTAssertEqual(second.lastSeenUID, 0)
    }

    func testMigratesLegacyCheckpoint() {
        let defaults = makeDefaults()
        let accountID = UUID()
        defaults.set(123, forKey: "mailbell.uidValidity")
        defaults.set(456, forKey: "mailbell.lastSeenUID")

        CheckpointStore.migrateLegacyCheckpoint(to: accountID, userDefaults: defaults)
        let migrated = CheckpointStore(accountID: accountID, userDefaults: defaults)

        XCTAssertEqual(migrated.storedUIDValidity, 123)
        XCTAssertEqual(migrated.lastSeenUID, 456)
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "mailbell.CheckpointStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
