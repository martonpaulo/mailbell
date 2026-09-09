@testable import mailbell
import XCTest

/// A bounded BODY.PEEK slice cuts a base64 payload anywhere, and some
/// transports fold it on spaces instead of CRLF. Both shapes used to reach the
/// user as raw base64.
final class Base64PreviewDecoderTests: XCTestCase {
    private let wrapped =
        "wqFKYW5lIHRlIGludml0w7MgYSBzdSBQbGFuIGZhbWlsaWFyIGRlIFByZW1pdW0gcG9yIDMgZMOt\nYXMgZ3JhdGlz"
        + "ISBDb24gdG9kb3MgbG9zIGJlbmVmaWNpb3MgZXhjbHVzaXZvcyBxdWUgeWEgY29u\nb2Nlcy4="
    private let truncatedAtResidueOne =
        "wqFKYW5lIHRlIGludml0w7MgYSBzdSBQbGFuIGZhbWlsaWFyIGRlIFByZW1pdW0gcG9yIDMgZMOt\nYXMgZ3JhdGlz"
        + "ISBDb24gdG9kb"
    private let spaceFolded =
        "wqFKYW5lIHRlIGludml0w7MgYSBzdSBQbGFuIGZhbWlsaWFyIGRlIFByZW1pdW0gcG9yIDMgZMOt"
        + "YXMgZ3JhdGlzISBDb24gdG9kb3MgbG9zIGJlbmVmaWNpb3MgZXhjbHVzaXZvcyBxdWUgeWEgY29u b2Nlcy4="

    func testDecodesWellFormedFoldedPayload() {
        let preview = EmailBodyPreviewSanitizer.preview(from: wrapped)

        XCTAssertNotNil(preview)
        XCTAssertTrue(
            preview?.hasPrefix("\u{a1}Jane te invit\u{f3} a su Plan familiar") == true,
            "got \(preview ?? "nil")"
        )
        XCTAssertFalse(preview?.contains("ICAgIMKh") == true)
    }

    func testDecodesPayloadTruncatedToAnUnpaddableLength() {
        // 101 base64 characters: length % 4 == 1, so no padding is valid and
        // the whole block used to be emitted raw.
        let preview = EmailBodyPreviewSanitizer.preview(from: truncatedAtResidueOne)

        XCTAssertNotNil(preview)
        XCTAssertTrue(
            preview?.hasPrefix("\u{a1}Jane te invit\u{f3} a su Plan familiar") == true,
            "got \(preview ?? "nil")"
        )
        XCTAssertFalse(preview?.contains("ICAgIMKh") == true)
    }

    func testDecodesPayloadFoldedOnSpaces() {
        let preview = EmailBodyPreviewSanitizer.preview(from: spaceFolded)

        XCTAssertNotNil(preview)
        XCTAssertTrue(
            preview?.hasPrefix("\u{a1}Jane te invit\u{f3}") == true,
            "got \(preview ?? "nil")"
        )
        XCTAssertFalse(preview?.contains("ICAgIMKh") == true)
    }

    func testLeavesOrdinaryProseAlone() {
        // Prose is also alphabet characters separated by spaces. Folding is
        // recognised by uniform wide chunks, which a sentence never has.
        let prose = "Reserve your seat today because the early rate ends on Friday"

        XCTAssertEqual(EmailBodyPreviewSanitizer.preview(from: prose), prose)
    }

    func testLeavesLongIdentifiersAlone() {
        let text = "Your reference is 4f9a2c7be1d84a35b0c6e2f71a9d3c85 for support"

        XCTAssertEqual(EmailBodyPreviewSanitizer.preview(from: text), text)
    }
}
