@testable import mailbell
import XCTest

final class IMAPParserTests: XCTestCase {
    func testParsesUntaggedCount() {
        XCTAssertEqual(IMAPParser.parseUntagged("* 12 EXISTS", suffix: "EXISTS"), 12)
        XCTAssertEqual(IMAPParser.parseUntagged("* 3 RECENT", suffix: "RECENT"), 3)
        XCTAssertNil(IMAPParser.parseUntagged("A0001 OK", suffix: "EXISTS"))
    }

    func testParsesBracketValues() {
        XCTAssertEqual(IMAPParser.parseBracket("* OK [UIDVALIDITY 12345] UIDs valid", key: "UIDVALIDITY"), 12345)
        XCTAssertEqual(IMAPParser.parseBracket("* OK [UIDNEXT 67890] Predicted next UID", key: "UIDNEXT"), 67890)
        XCTAssertNil(IMAPParser.parseBracket("* OK [PERMANENTFLAGS (\\Seen)]", key: "UIDVALIDITY"))
    }

    func testParsesHeaderFields() {
        let raw = "From: Sender <sender@example.com>\r\n"
            + "Subject: Hello\r\n"
            + "\tWorld\r\n"
            + "Date: Tue, 02 Jun 2026 12:00:00 +0000\r\n\r\n"
        let fields = IMAPParser.parseHeaderFields(raw)

        XCTAssertEqual(fields["from"], "Sender <sender@example.com>")
        XCTAssertEqual(fields["subject"], "Hello World")
        XCTAssertEqual(fields["date"], "Tue, 02 Jun 2026 12:00:00 +0000")
    }

    func testParsesFetchHeader() {
        let raw = "From: =?UTF-8?B?SmFuZQ==?=\r\n"
            + "Subject: =?UTF-8?Q?Hello_World=21?=\r\n"
            + "Date: Tue, 02 Jun 2026 12:00:00 +0000\r\n"
            + "Message-ID: <message@example.com>\r\n\r\n"
        let block = Data(raw.utf8)

        let firstLine = "* 23 FETCH (UID 456 X-GM-MSGID 987654321 "
            + "X-GM-THRID 123456789 BODY[HEADER.FIELDS (FROM SUBJECT DATE MESSAGE-ID)] {153}"
        let header = IMAPParser.parseFetch(firstLine: firstLine, headerBlock: block)

        XCTAssertEqual(header?.uid, 456)
        XCTAssertEqual(header?.from, "Jane")
        XCTAssertEqual(header?.subject, "Hello World!")
        XCTAssertEqual(header?.date, "Tue, 02 Jun 2026 12:00:00 +0000")
        XCTAssertEqual(header?.gmThreadId, "123456789")
        XCTAssertEqual(header?.gmMessageId, "987654321")
        XCTAssertEqual(header?.messageId, "<message@example.com>")
    }

    func testFetchWithoutLiteralIsIgnored() {
        let header = IMAPParser.parseFetch(
            firstLine: "* 23 FETCH (UID 456 X-GM-THRID 123456789)",
            headerBlock: Data()
        )

        XCTAssertNil(header)
    }
}
