@testable import mailbell
import XCTest

final class EmailBodyPreviewSanitizerTests: XCTestCase {
    func testPreviewStripsHTMLAndCollapsesUsefulText() {
        let raw = """
        <html><body><p>Hello&nbsp;<strong>Ana</strong>.</p><img src="cid:image">\
        <script>ignored()</script><style>.x { color: red; }</style></body></html>
        """

        XCTAssertEqual(
            EmailBodyPreviewSanitizer.preview(from: raw),
            "Hello Ana."
        )
    }

    func testPreviewDecodesQuotedPrintableAndTruncatesOnWordBoundary() {
        let raw = "Status=20da=20revis=C3=A3o=20do=20contrato=20com=20detalhes=20extras"

        XCTAssertEqual(
            EmailBodyPreviewSanitizer.preview(from: raw, limit: 32),
            "Status da revisão do contrato..."
        )
    }

    func testPreviewDropsMIMEPartHeaders() {
        let raw = """
        --boundary
        Content-Type: text/plain; charset=utf-8
        Content-Transfer-Encoding: quoted-printable

        Body=20only
        --boundary--
        """

        XCTAssertEqual(EmailBodyPreviewSanitizer.preview(from: raw), "Body only")
    }
}
