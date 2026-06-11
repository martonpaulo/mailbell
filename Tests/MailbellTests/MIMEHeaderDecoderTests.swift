@testable import mailbell
import XCTest

final class MIMEHeaderDecoderTests: XCTestCase {
    func testDecodesBase64EncodedWord() {
        XCTAssertEqual(MIMEHeaderDecoder.decode("=?UTF-8?B?SGVsbG8=?="), "Hello")
    }

    func testDecodesQuotedPrintableEncodedWord() {
        XCTAssertEqual(MIMEHeaderDecoder.decode("=?UTF-8?Q?Hello_World=21?="), "Hello World!")
    }

    func testLeavesPlainTextUnchanged() {
        XCTAssertEqual(MIMEHeaderDecoder.decode("Plain subject"), "Plain subject")
    }
}
