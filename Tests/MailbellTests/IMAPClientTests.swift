import Foundation
@testable import mailbell
import XCTest

final class IMAPClientTests: XCTestCase {
    func testMarkAsReadSendsSilentSeenStoreForUID() async throws {
        let connection = ScriptedIMAPConnection(lines: ["A0001 OK STORE completed"])
        let client = IMAPClient(connection: connection)

        try await client.markAsRead(uid: 42)

        XCTAssertEqual(connection.sentLines, ["A0001 UID STORE 42 +FLAGS.SILENT (\\Seen)"])
    }

    func testMarkAsReadRejectsInvalidUID() async {
        let client = IMAPClient(connection: ScriptedIMAPConnection(lines: []))

        do {
            try await client.markAsRead(uid: 0)
            XCTFail("Expected invalid UID to throw.")
        } catch let error as IMAPClient.IMAPError {
            XCTAssertEqual(error.localizedDescription, "Invalid IMAP UID: 0")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

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

private final class ScriptedIMAPConnection: IMAPClientTransport, @unchecked Sendable {
    private var lines: [String]
    private(set) var sentLines: [String] = []

    init(lines: [String]) {
        self.lines = lines
    }

    func connect() async throws {}

    func cancel() {}

    func send(_ line: String) async throws {
        sentLines.append(line)
    }

    func sendRaw(_ text: String) async throws {
        sentLines.append(text)
    }

    func readLine() async throws -> String {
        lines.removeFirst()
    }

    func readBytes(_: Int) async throws -> Data {
        Data()
    }
}
