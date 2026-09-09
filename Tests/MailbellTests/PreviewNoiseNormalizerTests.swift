@testable import mailbell
import XCTest

/// Preheader stuffing is invisible, so it is not whitespace and survives space
/// collapsing. Left in place it eats the whole preview budget.
final class PreviewNoiseNormalizerTests: XCTestCase {
    func testRemovesZeroWidthPreheaderStuffing() {
        let stuffing = String(repeating: "\u{200c}\u{00a0}", count: 40)
        let raw = "Avoid extra baggage fees at the gate" + stuffing + "Book your bag now."

        XCTAssertEqual(
            EmailBodyPreviewSanitizer.preview(from: raw),
            "Avoid extra baggage fees at the gate Book your bag now."
        )
    }

    func testRemovesStuffingWrittenAsHTMLEntities() {
        let raw = "<div>Avoid extra baggage fees at the gate"
            + String(repeating: "&zwnj;&nbsp;", count: 40)
            + "</div><div>Book your bag now.</div>"

        XCTAssertEqual(
            EmailBodyPreviewSanitizer.preview(from: raw),
            "Avoid extra baggage fees at the gate Book your bag now."
        )
    }

    func testKeepsASingleJoinerThatBuildsAnEmoji() {
        // One ZWJ between pictographs is the emoji, not padding.
        XCTAssertEqual(
            EmailBodyPreviewSanitizer.preview(from: "Team update \u{1f469}\u{200d}\u{1f4bb} shipped"),
            "Team update \u{1f469}\u{200d}\u{1f4bb} shipped"
        )
    }

    func testKeepsSingleJoinersInAMultiPersonEmoji() {
        // Each joiner sits alone between pictographs, so no run forms.
        let family = "\u{1f468}\u{200d}\u{1f469}\u{200d}\u{1f467}"

        XCTAssertEqual(EmailBodyPreviewSanitizer.preview(from: "Welcome \(family) home"), "Welcome \(family) home")
    }

    func testKeepsASingleNonJoinerThatIsLanguage() {
        // ZWNJ between letters is meaningful in Persian and the Indic scripts.
        let word = "\u{0645}\u{06cc}\u{200c}\u{0631}\u{0648}\u{0645}"

        XCTAssertEqual(EmailBodyPreviewSanitizer.preview(from: word), word)
    }

    func testKeepsAccentedText() {
        XCTAssertEqual(
            EmailBodyPreviewSanitizer.preview(from: "Réunion confirmée pour demain"),
            "Réunion confirmée pour demain"
        )
    }

    // MARK: - Decorative noise
    //
    // Drawn banners are already removed by the sanitizer's thematic-break rule.
    // These lock that in: it had no coverage, and #15 lists it as a criterion.

    func testRemovesDrawnDividerBanners() {
        let raw = "************************************\n"
            + "Your Dinner Spot is Confirmed\n"
            + "************************************\n"
            + "Hey Alex, see you Friday at 8."

        XCTAssertEqual(
            EmailBodyPreviewSanitizer.preview(from: raw),
            "Your Dinner Spot is Confirmed Hey Alex, see you Friday at 8."
        )
    }

    func testKeepsMeaningfulPunctuation() {
        // Ellipses, emphasis and an em-dash written as hyphens are not banners.
        let raw = "Wait... really?! The rate -- our best yet -- ends Friday."

        XCTAssertEqual(
            EmailBodyPreviewSanitizer.preview(from: raw),
            "Wait... really?! The rate -- our best yet -- ends Friday."
        )
    }

    func testDropsLeadingViewOnlineMarkerWhenTextFollows() {
        let raw = "<p>https://x.example/view</p><p>Your order shipped today.</p>"

        XCTAssertEqual(EmailBodyPreviewSanitizer.preview(from: raw), "Your order shipped today.")
    }

    func testKeepsInlineLinkMarkers() {
        let raw = "<p>Track it at https://x.example/t any time.</p>"

        XCTAssertEqual(EmailBodyPreviewSanitizer.preview(from: raw), "Track it at [URL] any time.")
    }

    func testKeepsALinkMarkerThatIsTheWholePreview() {
        let raw = "<p>https://x.example/view</p>"

        XCTAssertEqual(EmailBodyPreviewSanitizer.preview(from: raw), "[URL]")
    }
}
