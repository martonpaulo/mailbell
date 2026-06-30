@testable import mailbell
import XCTest

final class MIMEHeaderDecoderTests: XCTestCase {
    func testDecodesBase64EncodedWord() {
        XCTAssertEqual(MIMEHeaderDecoder.decode("=?UTF-8?B?SGVsbG8=?="), "Hello")
    }

    func testDecodesQuotedPrintableEncodedWord() {
        XCTAssertEqual(MIMEHeaderDecoder.decode("=?UTF-8?Q?Hello_World=21?="), "Hello World!")
    }

    func testDecodesQuotedPrintableEncodedWordStartingWithEscapedByte() {
        XCTAssertEqual(
            MIMEHeaderDecoder.decode("=?UTF-8?Q?=F0=9F=93=AC_Chegou_a_renova=C3=A7=C3=A3o?= Vida"),
            "📬 Chegou a renovação Vida"
        )
    }

    func testLeavesPlainTextUnchanged() {
        XCTAssertEqual(MIMEHeaderDecoder.decode("Plain subject"), "Plain subject")
    }
}
