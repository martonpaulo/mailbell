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

    func testPreviewUsesSwiftSoupForMalformedNestedHTML() {
        let raw = """
        <div><p>Hello <b>Ana<p>Second&nbsp;line <a href="https://example.com">with link</div>
        """

        XCTAssertEqual(
            EmailBodyPreviewSanitizer.preview(from: raw),
            "Hello Ana Second line with link"
        )
    }

    func testPreviewDropsNonVisibleAndNoisyMarkup() {
        let raw = """
        <html><head><title>Ignore title</title></head><body>
        <!-- comment should not appear -->
        <p>Visible text</p>
        <span hidden>hidden attribute</span>
        <span aria-hidden="true">aria hidden</span>
        <span style="display: none">display hidden</span>
        <span style="visibility:hidden">visibility hidden</span>
        </body></html>
        """

        XCTAssertEqual(
            EmailBodyPreviewSanitizer.preview(from: raw),
            "Visible text"
        )
    }

    func testPreviewDecodesBroadNamedAndNumericEntities() {
        let raw = "<p>Tom&amp;Jerry &mdash; caf&eacute; &#169; &#x1F514;</p>"

        XCTAssertEqual(
            EmailBodyPreviewSanitizer.preview(from: raw),
            "Tom&Jerry — café © 🔔"
        )
    }

    func testPlainTextComparisonsAreNotTreatedAsHTML() {
        let raw = "Use 2 < 3 and 5 > 4 in the filter."

        XCTAssertEqual(
            EmailBodyPreviewSanitizer.preview(from: raw),
            "Use 2 < 3 and 5 > 4 in the filter."
        )
    }

    func testPreviewReturnsNilWhenHTMLHasNoVisibleText() {
        let raw = """
        <html><head><style>.x{color:red}</style><script>ignored()</script></head>
        <body><span hidden>hidden</span></body></html>
        """

        XCTAssertNil(EmailBodyPreviewSanitizer.preview(from: raw))
    }

    func testParserFailureFallsBackWithoutRegexHTMLParser() {
        let raw = "<p>Useful &amp; bounded text</p>"

        let preview = EmailBodyPreviewSanitizer.preview(from: raw) { _ in
            throw CocoaError(.fileReadCorruptFile)
        }

        XCTAssertEqual(preview, "<p>Useful &amp; bounded text</p>")
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

    func testPreviewRemovesURLsAndLooseMIMEArtifacts() {
        let raw = """
        This is a multi-part message in MIME format.
        This message is in MIME format.
        MIME part ignored
        multipart/alternative; boundary=abc
        Open https://example.com/really/long/link?token=secret for details.
        """

        XCTAssertEqual(
            EmailBodyPreviewSanitizer.preview(from: raw),
            "Open URL for details."
        )
    }

    func testPreviewRemovesInlineMultipartBoilerplateWithoutDroppingUsefulText() {
        let raw = """
        This is a multipart message in MIME format. Saluton, kara Marton! Kiel vi fartas?
        Kiel iras viaj aferoj?
        """

        XCTAssertEqual(
            EmailBodyPreviewSanitizer.preview(from: raw),
            "Saluton, kara Marton! Kiel vi fartas? Kiel iras viaj aferoj?"
        )
    }

    func testPreviewWrapsLongTextIntoReadableLines() throws {
        let raw = [
            "Alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu nu xi omicron pi rho sigma tau",
            "upsilon phi chi psi omega alpha beta gamma delta epsilon zeta eta theta iota kappa",
            "lambda mu nu xi omicron."
        ].joined(separator: " ")

        let preview = try XCTUnwrap(EmailBodyPreviewSanitizer.preview(from: raw))
        let lines = preview.split(separator: "\n", omittingEmptySubsequences: true)

        XCTAssertGreaterThan(lines.count, 1)
        XCTAssertLessThanOrEqual(lines.count, 3)
        XCTAssertTrue(lines.allSatisfy { $0.count <= 83 })
    }
}
