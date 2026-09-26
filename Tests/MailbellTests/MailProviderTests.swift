@testable import Mailbell
@testable import MailbellKit
import XCTest

/// The notification half of the webmail URL; the provider rules are in
/// MailbellKitTests (#80).
final class MailProviderTests: XCTestCase {
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
