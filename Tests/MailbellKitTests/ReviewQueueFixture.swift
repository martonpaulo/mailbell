import MailbellTestSupport
import XCTest

@testable import MailbellKit

/// Shared fixtures for the store suites, so the files that exercise the queue
/// and its handled history cannot drift apart.
enum ReviewQueueFixture {
    @MainActor
    static func makeStore(defaults: UserDefaults? = nil) -> ReviewQueue {
        let persistence = HandledHistory(userDefaults: defaults ?? makeDefaults())
        return ReviewQueue(
            persistence: persistence,
            now: { Date(timeIntervalSince1970: 1_806_000_000) }
        )
    }

    static func makeDefaults() -> UserDefaults {
        let defaults = TestDefaults.make()
        return defaults
    }

    static func makeAccount(
        id: String = "11111111-1111-1111-1111-111111111111",
        email: String = "account@example.com"
    ) -> MailAccount {
        guard let uuid = UUID(uuidString: id) else {
            preconditionFailure("fixture account id \(id) is not a UUID")
        }
        return MailAccount(id: uuid, providerID: .gmail, email: email)
    }

    static func makeHeader(
        uid: Int = 1,
        mailbox: MessageMailbox = .inbox,
        mailboxName: String? = nil,
        subject: String = "Subject",
        gmMessageId: String? = nil,
        gmThreadId: String? = nil,
        messageId: String? = nil,
        bodyPreview: String? = nil
    ) -> MessageHeader {
        MessageHeader(
            uid: uid,
            mailbox: mailbox,
            mailboxName: mailboxName,
            from: "Sender <sender@example.com>",
            subject: subject,
            date: "Tue, 02 Jun 2026 12:00:00 +0000",
            gmThreadId: gmThreadId,
            gmMessageId: gmMessageId,
            messageId: messageId,
            bodyPreview: bodyPreview,
            uidValidity: 1
        )
    }

    static func makeSnapshot(
        mailbox: MessageMailbox = .inbox,
        mailboxName: String = "INBOX",
        uids: [Int]
    ) -> MailboxUnreadSnapshot {
        MailboxUnreadSnapshot(mailbox: mailbox, mailboxName: mailboxName, uidValidity: 1, unreadUIDs: Set(uids))
    }
}
