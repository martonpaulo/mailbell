@testable import mailbell
import UserNotifications
import XCTest

final class NotificationResponseActionTests: XCTestCase {
    func testDefaultNotificationClickOpensEmail() throws {
        let accountID = UUID()
        let url = try XCTUnwrap(URL(string: "https://mail.google.com/mail/u/0/#inbox/abc"))

        let action = NotificationManager.responseAction(
            actionIdentifier: UNNotificationDefaultActionIdentifier,
            userInfo: [
                notificationEmailIDKey: "email-id",
                notificationAccountIDKey: accountID.uuidString,
                notificationWebmailURLKey: url.absoluteString
            ]
        )

        XCTAssertEqual(action, .open(emailID: "email-id", accountID: accountID, url: url))
    }

    func testDismissNotificationActionDismissesEmail() {
        let action = NotificationManager.responseAction(
            actionIdentifier: notificationDismissActionIdentifier,
            userInfo: [
                notificationEmailIDKey: "email-id"
            ]
        )

        XCTAssertEqual(action, .dismiss(emailID: "email-id"))
    }
}
