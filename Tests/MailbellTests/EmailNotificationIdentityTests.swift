@testable import mailbell
import XCTest

/// Notification Center replaces a request that reuses an identifier, so the
/// identifier has to name the message rather than its number.
final class EmailNotificationIdentityTests: XCTestCase {
    func testTheReplacedAccountPlusUIDRuleWouldHaveCollided() {
        // Documents the defect this identity replaces: the old identifier was
        // "mailbell.<account>.<uid>", which Notification Center treats as the
        // same request for an Inbox and a Spam message sharing a UID.
        let accountID = UUID()
        let inbox = makeIdentityHeader(uid: 42, mailbox: .inbox, gmMessageId: "inbox-42")
        let spam = makeIdentityHeader(uid: 42, mailbox: .spam, gmMessageId: "spam-42")

        XCTAssertEqual(
            "mailbell.\(accountID.uuidString).\(inbox.uid)",
            "mailbell.\(accountID.uuidString).\(spam.uid)",
            "the old rule collided, which is why it was replaced"
        )
        XCTAssertNotEqual(
            EmailNotificationContentBuilder.requestIdentifier(accountID: accountID, header: inbox),
            EmailNotificationContentBuilder.requestIdentifier(accountID: accountID, header: spam)
        )
    }

    func testInboxAndSpamMessagesSharingAUIDGetDifferentRequestIdentifiers() {
        let accountID = UUID()
        let inbox = makeIdentityHeader(uid: 42, mailbox: .inbox, gmMessageId: "inbox-42")
        let spam = makeIdentityHeader(uid: 42, mailbox: .spam, gmMessageId: "spam-42")

        XCTAssertNotEqual(
            EmailNotificationContentBuilder.requestIdentifier(accountID: accountID, header: inbox),
            EmailNotificationContentBuilder.requestIdentifier(accountID: accountID, header: spam)
        )
    }

    func testFallbackIdentityStillSeparatesMailboxesWithoutGmailIdentifiers() {
        let accountID = UUID()
        let inbox = makeIdentityHeader(uid: 42, mailbox: .inbox, gmMessageId: nil)
        let spam = makeIdentityHeader(uid: 42, mailbox: .spam, gmMessageId: nil)

        XCTAssertNotEqual(
            EmailNotificationContentBuilder.requestIdentifier(accountID: accountID, header: inbox),
            EmailNotificationContentBuilder.requestIdentifier(accountID: accountID, header: spam)
        )
    }

    func testFallbackIdentityIsScopedToTheMailboxGeneration() {
        let accountID = UUID()
        let old = makeIdentityHeader(uid: 42, mailbox: .inbox, gmMessageId: nil, uidValidity: 1)
        let new = makeIdentityHeader(uid: 42, mailbox: .inbox, gmMessageId: nil, uidValidity: 2)

        XCTAssertNotEqual(
            EmailNotificationContentBuilder.requestIdentifier(accountID: accountID, header: old),
            EmailNotificationContentBuilder.requestIdentifier(accountID: accountID, header: new)
        )
    }

    func testRepeatedNotificationForTheSameMessageKeepsOneIdentifier() {
        let accountID = UUID()
        let first = makeIdentityHeader(uid: 42, mailbox: .inbox, gmMessageId: "stable")
        // Same message, re-fetched with a preview and a different UID view.
        let second = makeIdentityHeader(uid: 99, mailbox: .inbox, gmMessageId: "stable")

        XCTAssertEqual(
            EmailNotificationContentBuilder.requestIdentifier(accountID: accountID, header: first),
            EmailNotificationContentBuilder.requestIdentifier(accountID: accountID, header: second)
        )
    }

    func testDifferentAccountsNeverShareARequestIdentifier() {
        let header = makeIdentityHeader(uid: 42, mailbox: .inbox, gmMessageId: "same")

        XCTAssertNotEqual(
            EmailNotificationContentBuilder.requestIdentifier(accountID: UUID(), header: header),
            EmailNotificationContentBuilder.requestIdentifier(accountID: UUID(), header: header)
        )
    }

    private func makeIdentityHeader(
        uid: Int,
        mailbox: MessageMailbox,
        gmMessageId: String?,
        uidValidity: Int = 1
    ) -> MessageHeader {
        MessageHeader(
            uid: uid,
            mailbox: mailbox,
            from: "sender@example.com",
            subject: "Subject",
            date: "",
            gmThreadId: nil,
            gmMessageId: gmMessageId,
            uidValidity: uidValidity
        )
    }
}
