import Foundation
@testable import mailbell
import XCTest

final class IMAPClientTests: XCTestCase {
    func testIdleReturnsMailboxChangedOnFlagUpdate() async throws {
        let connection = ScriptedIMAPConnection(lines: [
            "+ idling",
            "* 23 FETCH (FLAGS (\\Seen))",
            "A0001 OK IDLE completed"
        ])
        let client = IMAPClient(connection: connection)

        let event = try await client.idle(timeout: 60)

        XCTAssertEqual(event, .mailboxChanged)
        XCTAssertEqual(connection.sentLines, ["A0001 IDLE", "DONE\r\n"])
    }

    func testIdleReturnsNewMessagesWithExistsCount() async throws {
        let connection = ScriptedIMAPConnection(lines: [
            "+ idling",
            "* 7 EXISTS",
            "A0001 OK IDLE completed"
        ])
        let client = IMAPClient(connection: connection)

        let event = try await client.idle(timeout: 60)

        XCTAssertEqual(event, .newMessages(exists: 7))
        XCTAssertEqual(connection.sentLines, ["A0001 IDLE", "DONE\r\n"])
    }

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

    func testFetchHeadersChunksLargeUIDSets() async throws {
        let connection = ScriptedIMAPConnection(lines: [
            "A0001 OK FETCH completed",
            "A0002 OK FETCH completed"
        ])
        let client = IMAPClient(connection: connection)

        let headers = try await client.fetchHeaders(uids: Array(1 ... 101))

        XCTAssertTrue(headers.isEmpty)
        XCTAssertEqual(
            connection.sentLines,
            [
                "A0001 UID FETCH 1:100 (UID X-GM-MSGID X-GM-THRID BODY.PEEK[HEADER.FIELDS (FROM SUBJECT DATE MESSAGE-ID)])",
                "A0002 UID FETCH 101 (UID X-GM-MSGID X-GM-THRID BODY.PEEK[HEADER.FIELDS (FROM SUBJECT DATE MESSAGE-ID)])"
            ]
        )
    }

    func testFetchHeadersAddsSanitizedBodyPreview() async throws {
        let headerBlock = Data(
            """
            From: Ana <ana@example.com>\r
            Subject: Status\r
            Date: Tue, 02 Jun 2026 12:00:00 +0000\r
            Message-ID: <message@example.com>\r
            \r
            """.utf8
        )
        let bodyBlock = Data("<p>Hello&nbsp;<b>there</b>.</p>".utf8)
        let connection = ScriptedIMAPConnection(
            lines: [
                "* 1 FETCH (UID 42 X-GM-MSGID 100 X-GM-THRID 200 BODY[HEADER.FIELDS (FROM SUBJECT DATE MESSAGE-ID)] {\(headerBlock.count)}",
                ")",
                "A0001 OK FETCH completed",
                "* 1 FETCH (UID 42 BODY[TEXT]<0> {\(bodyBlock.count)}",
                ")",
                "A0002 OK FETCH completed"
            ],
            byteChunks: [headerBlock, bodyBlock]
        )
        let client = IMAPClient(connection: connection)

        let headers = try await client.fetchHeaders(uids: [42])

        XCTAssertEqual(headers.first?.bodyPreview, "Hello there.")
        XCTAssertEqual(
            connection.sentLines,
            [
                "A0001 UID FETCH 42 (UID X-GM-MSGID X-GM-THRID BODY.PEEK[HEADER.FIELDS (FROM SUBJECT DATE MESSAGE-ID)])",
                "A0002 UID FETCH 42 (UID BODY.PEEK[TEXT]<0.8192>)"
            ]
        )
    }

    func testSearchUnreadUIDsFromUIDScopesUnreadSearch() async throws {
        let connection = ScriptedIMAPConnection(lines: ["* SEARCH 42 43", "A0001 OK SEARCH completed"])
        let client = IMAPClient(connection: connection)

        let uids = try await client.searchUnreadUIDs(fromUID: 42)

        XCTAssertEqual(uids, [42, 43])
        XCTAssertEqual(connection.sentLines, ["A0001 UID SEARCH UID 42:* UNSEEN"])
    }
}

private final class ScriptedIMAPConnection: IMAPClientTransport, @unchecked Sendable {
    private var lines: [String]
    private var byteChunks: [Data]
    private(set) var sentLines: [String] = []

    init(lines: [String], byteChunks: [Data] = []) {
        self.lines = lines
        self.byteChunks = byteChunks
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
        guard !byteChunks.isEmpty else { return Data() }
        return byteChunks.removeFirst()
    }
}
