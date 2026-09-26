import MailbellTestSupport
import XCTest

@testable import MailbellKit

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

    private func makeDefaults() -> UserDefaults {
        let defaults = TestDefaults.make()
        return defaults
    }
}
