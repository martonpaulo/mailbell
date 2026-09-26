@testable import Mailbell
@testable import MailbellKit
import XCTest

/// The title of a fetched message: `MessageSubjectSanitizer` turns the raw
/// Subject into display text when IMAPClient parses the header, then
/// `EmailHeaderFormatter` adds the fallback and the spam marker (#80).
final class EmailHeaderFormatterTitleTests: XCTestCase {
    func testTitlePrefixesSpamMailbox() {
        let title = EmailHeaderFormatter.title(
            for: MessageHeader(
                uid: 1,
                mailbox: .spam,
                from: "Sender <sender@example.com>",
                subject: "Limited time offer",
                date: "",
                gmThreadId: nil
            )
        )

        XCTAssertEqual(title, "(SPAM) Limited time offer")
    }

    func testTitleDoesNotDuplicateExistingSpamMarker() {
        let title = EmailHeaderFormatter.title(
            for: MessageHeader(
                uid: 1,
                mailbox: .spam,
                from: "Sender <sender@example.com>",
                subject: "[SPAM] Limited time offer",
                date: "",
                gmThreadId: nil
            )
        )

        XCTAssertEqual(title, "[SPAM] Limited time offer")
    }

    func testTitleDecodesAndSanitizesEncodedSubject() {
        let title = EmailHeaderFormatter.title(
            for: MessageHeader(
                uid: 1,
                from: "Sender <sender@example.com>",
                subject: MessageSubjectSanitizer.displayText(from: "=?UTF-8?Q?=F0=9F=93=AC_Chegou_a_renova=C3=A7=C3=A3o_do_seu_seguro?= Vida"),
                date: "",
                gmThreadId: nil
            )
        )

        XCTAssertEqual(title, "📬 Chegou a renovação do seu seguro Vida")
    }

    func testTitleAppliesPreviewTokenSanitization() {
        let title = EmailHeaderFormatter.title(
            for: MessageHeader(
                uid: 1,
                from: "Sender <sender@example.com>",
                subject: MessageSubjectSanitizer.displayText(from: #"Open https://example.com/renew?token=secret <img src="cid:promo">"#),
                date: "",
                gmThreadId: nil
            )
        )

        XCTAssertEqual(title, "Open [URL] [IMG]")
    }

    func testTitleFallsBackWhenSanitizedSubjectHasNoVisibleText() {
        let title = EmailHeaderFormatter.title(
            for: MessageHeader(
                uid: 1,
                from: "Sender <sender@example.com>",
                subject: MessageSubjectSanitizer.displayText(from: "<html><head><script>ignored()</script></head><body hidden>ignored</body></html>"),
                date: "",
                gmThreadId: nil
            )
        )

        XCTAssertEqual(title, "(no subject)")
    }
}
