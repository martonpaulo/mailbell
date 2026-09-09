@testable import mailbell
import XCTest

/// A bounded BODY.PEEK slice can arrive without the <style> element that
/// enclosed its rules, which is how CSS reached notification previews.
final class EmailBodyPreviewStylesheetTests: XCTestCase {
    func testPreviewDropsStylesheetThatLostItsOpeningStyleTag() {
        // The bounded slice began inside the stylesheet, so only the closing
        // tag survives and SwiftSoup has no element to remove.
        let raw = """
        body, table, td, h1, h2, h3, p { font-family: Arial, Helvetica, sans-serif!important; \
        border-collapse: collapse; }
        .btn { color: #fff; }
        </style></head><body><p>Real teaser text here</p></body></html>
        """

        XCTAssertEqual(EmailBodyPreviewSanitizer.preview(from: raw), "Real teaser text here")
    }
}
