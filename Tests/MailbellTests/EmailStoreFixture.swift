@testable import mailbell
import XCTest

/// Shared fixtures for the store suites, so the files that exercise the queue
/// and its handled history cannot drift apart.
enum EmailStoreFixture {
    @MainActor
    static func makeStore(defaults: UserDefaults? = nil) -> EmailStore {
        let persistence = EmailStorePersistence(userDefaults: defaults ?? makeDefaults())
        return EmailStore(
            persistence: persistence,
            now: { Date(timeIntervalSince1970: 1_806_000_000) }
        )
    }

    static func makeDefaults() -> UserDefaults {
        let suiteName = "mailbell.EmailStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    static func makeAccount() -> MailAccount {
        MailAccount(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            providerID: .gmail,
            email: "account@example.com"
        )
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
