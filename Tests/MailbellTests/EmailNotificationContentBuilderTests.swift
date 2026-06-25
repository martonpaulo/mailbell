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

    func testBodyPreviewBecomesNotificationBodyWithSubjectSubtitle() throws {
        let content = try EmailNotificationContentBuilder.build(
            header: MessageHeader(
                uid: 4,
                from: "Ana Silva <ana@example.com>",
                subject: "Status update",
                date: "",
                gmThreadId: nil,
                bodyPreview: "The contract is ready for review."
            ),
            webmailURL: XCTUnwrap(URL(string: "https://mail.google.com/")),
            accountID: UUID()
        )

        XCTAssertEqual(content.title, "Ana Silva")
        XCTAssertEqual(content.subtitle, "Status update")
        XCTAssertEqual(content.body, "The contract is ready for review.")
    }

    func testSpamNotificationPrefixesSubjectSubtitle() throws {
        let content = try EmailNotificationContentBuilder.build(
            header: MessageHeader(
                uid: 5,
                mailbox: .spam,
                from: "Promo <promo@example.com>",
                subject: "Limited time offer",
                date: "",
                gmThreadId: nil,
                bodyPreview: "Act now."
            ),
            webmailURL: XCTUnwrap(URL(string: "https://mail.google.com/")),
            accountID: UUID()
        )

        XCTAssertEqual(content.title, "Promo")
        XCTAssertEqual(content.subtitle, "(SPAM) Limited time offer")
        XCTAssertEqual(content.body, "Act now.")
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

    func testThreadNotificationUsesSpecificMessagePreview() {
        let account = MailAccount(providerID: .gmail, email: "account@example.com")
        let firstHeader = MessageHeader(
            uid: 10,
            from: "Ana Silva <ana@example.com>",
            subject: "First thread message",
            date: "",
            gmThreadId: "thread-1",
            gmMessageId: "message-1",
            bodyPreview: "First preview"
        )
        let secondHeader = MessageHeader(
            uid: 11,
            from: "Ana Silva <ana@example.com>",
            subject: "Second thread message",
            date: "",
            gmThreadId: firstHeader.gmThreadId,
            gmMessageId: "message-2",
            bodyPreview: "Second preview"
        )

        let content = NotificationManager.notificationContent(for: secondHeader, account: account)

        XCTAssertEqual(content.title, "Ana Silva")
        XCTAssertEqual(content.subtitle, "Second thread message")
        XCTAssertEqual(content.body, "Second preview")
        XCTAssertEqual(
            content.userInfo[notificationEmailIDKey] as? String,
            EmailStoreIdentity.id(accountID: account.id, header: secondHeader)
        )
    }

    func testTestNotificationUsesSharedEmailFormatterShape() {
        let account = MailAccount(providerID: .gmail, email: "account@example.com")
        let content = NotificationManager.testNotificationContent(account: account)

        XCTAssertEqual(content.title, "Taylor Reed")
        XCTAssertEqual(content.subtitle, "Contract review today")
        XCTAssertEqual(content.body, "Please review the updated contract notes before the afternoon sync.")
        XCTAssertEqual(content.userInfo[notificationAccountIDKey] as? String, account.id.uuidString)
    }

    func testTestNotificationWithoutAccountDoesNotInventAccountIdentifier() {
        let content = NotificationManager.testNotificationContent(account: nil)

        XCTAssertNil(content.userInfo[notificationAccountIDKey])
        XCTAssertNotNil(content.userInfo[notificationWebmailURLKey])
    }
}
