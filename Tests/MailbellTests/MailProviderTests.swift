@testable import mailbell
import XCTest

final class MailProviderTests: XCTestCase {
    func testGmailProviderUsesGenericWebmailURL() {
        let provider = MailProviderRegistry.provider(for: .gmail)

        XCTAssertEqual(provider.webmailURL.absoluteString, "https://mail.google.com/")
        XCTAssertEqual(provider.capabilities.supportsThreadLink, true)
    }

    func testGmailProviderUsesThreadURLWhenThreadIDIsAvailable() {
        let provider = MailProviderRegistry.provider(for: .gmail)
        let header = MessageHeader(
            uid: 1,
            from: "sender@example.com",
            subject: "Subject",
            date: "",
            gmThreadId: "123456789"
        )

        XCTAssertEqual(
            provider.webmailURL(for: header).absoluteString,
            "https://mail.google.com/mail/#inbox/75bcd15"
        )
    }

    func testGmailProviderDoesNotHardcodeAccountIndexForThreadURL() {
        let provider = MailProviderRegistry.provider(for: .gmail)
        let account = MailAccount(providerID: .gmail, email: "user@example.com")
        let header = MessageHeader(
            uid: 1,
            from: "sender@example.com",
            subject: "Subject",
            date: "",
            gmThreadId: "123456789"
        )

        let url = provider.webmailURL(for: header, account: account).absoluteString

        XCTAssertEqual(url, "https://mail.google.com/mail/#inbox/75bcd15")
        XCTAssertFalse(url.contains("/mail/u/0/"))
    }

    func testGmailProviderFallsBackToGenericURLWithoutThreadID() {
        let provider = MailProviderRegistry.provider(for: .gmail)
        let header = MessageHeader(
            uid: 1,
            from: "sender@example.com",
            subject: "Subject",
            date: "",
            gmThreadId: nil
        )

        XCTAssertEqual(provider.webmailURL(for: header), provider.webmailURL)
    }

    func testGmailProviderFallsBackToGenericURLWithInvalidThreadID() {
        let provider = MailProviderRegistry.provider(for: .gmail)
        let header = MessageHeader(
            uid: 1,
            from: "sender@example.com",
            subject: "Subject",
            date: "",
            gmThreadId: "not-a-thread-id"
        )

        XCTAssertEqual(provider.webmailURL(for: header), provider.webmailURL)
    }

    func testNotificationWebmailURLUsesThreadURL() {
        let account = MailAccount(providerID: .gmail, email: "user@example.com")
        let header = MessageHeader(
            uid: 1,
            from: "sender@example.com",
            subject: "Subject",
            date: "",
            gmThreadId: "123456789"
        )

        XCTAssertEqual(
            NotificationManager.webmailURL(for: header, account: account).absoluteString,
            "https://mail.google.com/mail/#inbox/75bcd15"
        )
    }
}
