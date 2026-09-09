@testable import mailbell
import XCTest

/// Mail that declares iso-8859-1 is usually Windows-1252 on the wire. Latin-1
/// has no 0x80-0x9F range, so decoding it that way silently drops the euro sign
/// and curly quotes instead of failing.
final class EmailBodyPreviewCharsetTests: XCTestCase {
    func testDecodesWindows1252PunctuationInsteadOfDroppingIt() {
        let bytes = Data([
            0x50, 0x72, 0x65, 0x63, 0x69, 0x6F, 0x3A, 0x20, 0x32, 0x35, // "Precio: 25"
            0x80,                                                       // euro sign
            0x20, 0x93,                                                 // space, left curly quote
            0x63, 0x6F, 0x6E, 0x66, 0x69, 0x72, 0x6D, 0x61, 0x64, 0x6F, // "confirmado"
            0x94                                                        // right curly quote
        ])

        XCTAssertEqual(EmailBodyPreviewSanitizer.preview(from: bytes), "Precio: 25€ “confirmado”")
    }

    func testStillDecodesTrueLatin1Text() {
        // "Avión confirmado" in ISO-8859-1: the accented bytes are shared with
        // Windows-1252, so the wider decoder must not change this result.
        let bytes = Data([0x41, 0x76, 0x69, 0xF3, 0x6E, 0x20, 0x6D, 0x61, 0xF1, 0x61, 0x6E, 0x61])

        XCTAssertEqual(EmailBodyPreviewSanitizer.preview(from: bytes), "Avión mañana")
    }

    func testPrefersUTF8WhenTheBytesAreValidUTF8() {
        let bytes = Data("Réunion confirmée".utf8)

        XCTAssertEqual(EmailBodyPreviewSanitizer.preview(from: bytes), "Réunion confirmée")
    }
}
