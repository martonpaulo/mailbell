@testable import mailbell
import XCTest

final class IMAPParserTests: XCTestCase {
    func testParsesInternalDateFromEitherSideOfTheHeaderLiteral() {
        let headerBlock = Data("From: a@example.com\r\nSubject: S\r\n\r\n".utf8)
        let expected = Date(timeIntervalSince1970: 1_780_401_600) // 2026-06-02 12:00:00Z

        let leading = IMAPParser.parseFetch(
            firstLine: #"* 1 FETCH (UID 7 INTERNALDATE "02-Jun-2026 12:00:00 +0000" BODY[HEADER.FIELDS (FROM)] {40}"#,
            headerBlock: headerBlock
        )
        XCTAssertEqual(leading?.serverReceivedAt, expected)

        let trailing = IMAPParser.parseFetch(
            firstLine: #"* 1 FETCH (UID 7 BODY[HEADER.FIELDS (FROM)] {40}"#,
            trailingLine: #" INTERNALDATE "02-Jun-2026 12:00:00 +0000")"#,
            headerBlock: headerBlock
        )
        XCTAssertEqual(trailing?.serverReceivedAt, expected)
        XCTAssertEqual(trailing?.uid, 7)
    }

    func testParsesInternalDateWithSpacePaddedDayAndNonZeroOffset() {
        // RFC 3501 space-pads single-digit days.
        XCTAssertEqual(
            IMAPParser.parseInternalDate(in: #"(INTERNALDATE " 2-Jun-2026 09:00:00 -0300")"#),
            Date(timeIntervalSince1970: 1_780_401_600)
        )
        XCTAssertEqual(
            IMAPParser.parseInternalDate(in: #"(INTERNALDATE "02-Jun-2026 14:30:00 +0230")"#),
            Date(timeIntervalSince1970: 1_780_401_600)
        )
    }

    func testRejectsMalformedOrAbsentInternalDate() {
        XCTAssertNil(IMAPParser.parseInternalDate(in: #"(UID 7 FLAGS (\Seen))"#))
        XCTAssertNil(IMAPParser.parseInternalDate(in: #"(INTERNALDATE "not a date")"#))
        XCTAssertNil(IMAPParser.parseInternalDate(in: #"(INTERNALDATE "02-Jun-2026 12:00:00 +0000"#))
    }

    func testHeaderBodyCannotForgeFetchAttributes() {
        // Text inside the message must never be read as server metadata.
        let forged = Data(("From: a@example.com\r\n"
            + "Subject: INTERNALDATE \"01-Jan-2000 00:00:00 +0000\"\r\n\r\n").utf8)
        let header = IMAPParser.parseFetch(
            firstLine: #"* 1 FETCH (UID 7 BODY[HEADER.FIELDS (FROM SUBJECT)] {70}"#,
            headerBlock: forged
        )

        XCTAssertNil(header?.serverReceivedAt)
    }

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

    func testParsesSearchUIDs() {
        XCTAssertEqual(IMAPParser.parseSearchUIDs("* SEARCH 101 102 250"), [101, 102, 250])
        XCTAssertEqual(IMAPParser.parseSearchUIDs("* SEARCH"), [])
        XCTAssertNil(IMAPParser.parseSearchUIDs("* 12 EXISTS"))
        XCTAssertNil(IMAPParser.parseSearchUIDs("A0001 OK SEARCH completed"))
    }

    func testParsesSpecialUseJunkMailbox() {
        let line = #"* LIST (\HasNoChildren \Junk) "/" "[Gmail]/Spam""#

        XCTAssertEqual(IMAPParser.parseSpecialUseMailbox(line, flag: "\\Junk"), "[Gmail]/Spam")
        XCTAssertNil(IMAPParser.parseSpecialUseMailbox(line, flag: "\\Trash"))
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
