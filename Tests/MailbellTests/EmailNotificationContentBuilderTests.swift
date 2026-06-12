@testable import mailbell
import XCTest

final class EmailNotificationContentBuilderTests: XCTestCase {
    func testSenderNameBecomesNotificationTitle() throws {
        let content = try EmailNotificationContentBuilder.build(
            header: MessageHeader(
                uid: 1,
                from: "Ana Silva <ana@example.com>",
                subject: "Revisão do contrato hoje",
                date: "",
                gmThreadId: nil
            ),
            webmailURL: XCTUnwrap(URL(string: "https://mail.google.com/")),
            accountID: UUID()
        )

        XCTAssertEqual(content.title, "Ana Silva")
        XCTAssertEqual(content.subtitle, "")
        XCTAssertEqual(content.body, "Revisão do contrato hoje")
    }

    func testSenderEmailBecomesNotificationTitleWhenNameIsMissing() throws {
        let content = try EmailNotificationContentBuilder.build(
            header: MessageHeader(
                uid: 2,
                from: "<ana@example.com>",
                subject: "Status update",
                date: "",
                gmThreadId: nil
            ),
            webmailURL: XCTUnwrap(URL(string: "https://mail.google.com/")),
            accountID: UUID()
        )

        XCTAssertEqual(content.title, "ana@example.com")
        XCTAssertEqual(content.subtitle, "")
        XCTAssertEqual(content.body, "Status update")
    }

    func testRealNotificationContentUsesSharedEmailFormatter() {
        let account = MailAccount(providerID: .gmail, email: "account@example.com")
        let header = MessageHeader(
            uid: 3,
            from: "\"Ana Silva\" <ana@example.com>",
            subject: "Shared formatter",
            date: "",
            gmThreadId: nil,
            gmMessageId: "123"
        )

        let content = NotificationManager.notificationContent(for: header, account: account)

        XCTAssertEqual(content.title, "Ana Silva")
        XCTAssertEqual(content.subtitle, "")
        XCTAssertEqual(content.body, "Shared formatter")
        XCTAssertEqual(content.categoryIdentifier, notificationEmailCategoryIdentifier)
        XCTAssertEqual(content.userInfo[notificationAccountIDKey] as? String, account.id.uuidString)
        XCTAssertEqual(
            content.userInfo[notificationEmailIDKey] as? String,
            EmailStoreIdentity.id(accountID: account.id, header: header)
        )
    }

    func testTestNotificationUsesSharedEmailFormatterShape() {
        let account = MailAccount(providerID: .gmail, email: "account@example.com")
        let content = NotificationManager.testNotificationContent(account: account)

        XCTAssertEqual(content.title, "Ana Silva")
        XCTAssertEqual(content.subtitle, "")
        XCTAssertEqual(content.body, "Revisão do contrato hoje")
        XCTAssertEqual(content.userInfo[notificationAccountIDKey] as? String, account.id.uuidString)
    }

    func testTestNotificationWithoutAccountDoesNotInventAccountIdentifier() {
        let content = NotificationManager.testNotificationContent(account: nil)

        XCTAssertNil(content.userInfo[notificationAccountIDKey])
        XCTAssertNotNil(content.userInfo[notificationWebmailURLKey])
    }
}
