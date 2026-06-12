@testable import mailbell
import XCTest

final class IMAPClientTests: XCTestCase {
    func testUIDSequenceSetDeduplicatesSortsAndCompressesConsecutiveUIDs() {
        let sequenceSet = IMAPClient.uidSequenceSet(for: [12, 10, 11, 7, 7, 3])

        XCTAssertEqual(sequenceSet, "3,7,10:12")
    }

    func testUIDSequenceSetOmitsInvalidUIDs() {
        let sequenceSet = IMAPClient.uidSequenceSet(for: [0, -1, 5])

        XCTAssertEqual(sequenceSet, "5")
    }

    func testUIDSequenceSetIsEmptyWithoutPositiveUIDs() {
        let sequenceSet = IMAPClient.uidSequenceSet(for: [0, -1])

        XCTAssertTrue(sequenceSet.isEmpty)
    }
}
