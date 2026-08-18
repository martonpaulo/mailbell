@testable import mailbell
import UserNotifications
import XCTest

final class EmailNotificationContentBuilderTests: XCTestCase {
    func testEmailNotificationSoundFollowsPreference() throws {
        let header = MessageHeader(
            uid: 1,
            from: "Ana Silva <ana@example.com>",
            subject: "Status update",
            date: "",
            gmThreadId: nil
        )
        let url = try XCTUnwrap(URL(string: "https://mail.google.com/"))

        let audible = EmailNotificationContentBuilder.build(
            header: header,
            webmailURL: url,
            accountID: UUID(),
            playNotificationSounds: true
        )
        let silent = EmailNotificationContentBuilder.build(
            header: header,
            webmailURL: url,
            accountID: UUID(),
            playNotificationSounds: false
        )

        XCTAssertEqual(audible.sound, UNNotificationSound.default)
        XCTAssertNil(silent.sound)
    }

    func testTestNotificationSoundFollowsPreference() {
        let account = MailAccount(providerID: .gmail, email: "account@example.com")

        let audible = NotificationManager.testNotificationContent(
            account: account,
            playNotificationSounds: true
        )
        let silent = NotificationManager.testNotificationContent(
            account: account,
            playNotificationSounds: false
        )

        XCTAssertEqual(audible.sound, UNNotificationSound.default)
        XCTAssertNil(silent.sound)
    }

    func testSignInNotificationSoundFollowsPreference() {
        let account = MailAccount(providerID: .gmail, email: "account@example.com")

        let audible = SignInNotificationContentBuilder.build(
            account: account,
            playNotificationSounds: true
        )
        let silent = SignInNotificationContentBuilder.build(
            account: account,
            playNotificationSounds: false
        )

        XCTAssertEqual(audible.sound, UNNotificationSound.default)
        XCTAssertNil(silent.sound)
    }

    func testForegroundPresentationSoundFollowsNotificationContent() {
        let audible = UNMutableNotificationContent()
        audible.sound = .default
        let silent = UNMutableNotificationContent()

        let audibleOptions = NotificationManager.presentationOptions(for: audible)
        let silentOptions = NotificationManager.presentationOptions(for: silent)

        XCTAssertTrue(audibleOptions.contains(.banner))
        XCTAssertTrue(audibleOptions.contains(.sound))
        XCTAssertTrue(silentOptions.contains(.banner))
        XCTAssertFalse(silentOptions.contains(.sound))
    }

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
            accountID: UUID(),
            playNotificationSounds: true
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
            accountID: UUID(),
            playNotificationSounds: true
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
            accountID: UUID(),
            playNotificationSounds: true
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
            accountID: UUID(),
            playNotificationSounds: true
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

        let content = NotificationManager.notificationContent(
            for: header,
            account: account,
            playNotificationSounds: true
        )

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

        let content = NotificationManager.notificationContent(
            for: secondHeader,
            account: account,
            playNotificationSounds: true
        )

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
        let content = NotificationManager.testNotificationContent(
            account: account,
            playNotificationSounds: true
        )

        XCTAssertEqual(content.title, "Taylor Reed")
        XCTAssertEqual(content.subtitle, "Contract review today")
        XCTAssertEqual(content.body, "Please review the updated contract notes before the afternoon sync.")
        XCTAssertEqual(content.userInfo[notificationAccountIDKey] as? String, account.id.uuidString)
    }

    func testTestNotificationWithoutAccountDoesNotInventAccountIdentifier() {
        let content = NotificationManager.testNotificationContent(
            account: nil,
            playNotificationSounds: true
        )

        XCTAssertNil(content.userInfo[notificationAccountIDKey])
        XCTAssertNotNil(content.userInfo[notificationWebmailURLKey])
    }

    func testSignInNotificationNamesTheAccountAndCollapsesPerAccount() {
        let account = MailAccount(providerID: .gmail, email: "account@example.com")
        let content = SignInNotificationContentBuilder.build(
            account: account,
            playNotificationSounds: true
        )

        XCTAssertEqual(content.title, "Sign in needed")
        XCTAssertTrue(content.body.contains(account.email))
        XCTAssertEqual(
            SignInNotificationContentBuilder.requestIdentifier(accountID: account.id),
            "mailbell.signin.\(account.id.uuidString)"
        )
    }
}
