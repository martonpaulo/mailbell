import MailbellTestSupport
import XCTest

@testable import MailbellKit

/// The review queue is a recent, reconstructible window over Gmail. Without a
/// bound on retained messages it grows with the mailbox; without a bound on
/// rows the menu does. Gmail stays authoritative for everything outside it.
final class ReviewQueueRetentionTests: XCTestCase {
    @MainActor
    func testAnAccountRetainsAtMostItsMessageBudget() throws {
        let store = makeStore()
        let account = makeAccount()

        for uid in 1...(ReviewQueueBudget.retainedMessagesPerAccount + 120) {
            _ = try store.admit(header: makeHeader(uid: uid), account: account)
        }

        XCTAssertEqual(
            store.retainedMessageCount(accountID: account.id),
            ReviewQueueBudget.retainedMessagesPerAccount
        )
    }

    @MainActor
    func testEachAccountGetsItsOwnBudget() throws {
        let store = makeStore()
        let first = makeAccount()
        let second = makeAccount(id: "55555555-5555-5555-5555-555555555555", email: "other@example.com")

        for uid in 1...(ReviewQueueBudget.retainedMessagesPerAccount + 50) {
            _ = try store.admit(header: makeHeader(uid: uid), account: first)
            _ = try store.admit(header: makeHeader(uid: uid), account: second)
        }

        XCTAssertEqual(
            store.retainedMessageCount(accountID: first.id),
            ReviewQueueBudget.retainedMessagesPerAccount
        )
        XCTAssertEqual(
            store.retainedMessageCount(accountID: second.id),
            ReviewQueueBudget.retainedMessagesPerAccount
        )
    }

    @MainActor
    func testTheMenuShowsAtMostTheVisibleConversationBudget() throws {
        let store = makeStore()
        let account = makeAccount()
        let conversations = ReviewQueueBudget.shownConversationsPerAccount + 20

        for uid in 1...conversations {
            _ = try store.admit(header: makeHeader(uid: uid, gmThreadId: "T\(uid)"), account: account)
        }

        XCTAssertEqual(store.shownItems.count, ReviewQueueBudget.shownConversationsPerAccount)
        XCTAssertEqual(store.hiddenConversationCount(accountID: account.id), 20)
        XCTAssertEqual(store.retainedMessageCount(accountID: account.id), conversations)
    }

    @MainActor
    func testRowsAreCappedPerAccountRatherThanOverall() throws {
        let store = makeStore()
        let first = makeAccount()
        let second = makeAccount(id: "55555555-5555-5555-5555-555555555555", email: "other@example.com")
        let conversations = ReviewQueueBudget.shownConversationsPerAccount + 5

        for uid in 1...conversations {
            _ = try store.admit(header: makeHeader(uid: uid, gmThreadId: "T\(uid)"), account: first)
            _ = try store.admit(header: makeHeader(uid: uid, gmThreadId: "T\(uid)"), account: second)
        }

        XCTAssertEqual(store.shownItems.count, ReviewQueueBudget.shownConversationsPerAccount * 2)
    }

    @MainActor
    func testEvictionNeverRecordsADisposition() throws {
        let store = makeStore()
        let account = makeAccount()
        let oldest = makeHeader(uid: 1)
        _ = try store.admit(header: oldest, account: account)

        for uid in 2...(ReviewQueueBudget.retainedMessagesPerAccount + 40) {
            _ = try store.admit(header: makeHeader(uid: uid), account: account)
        }

        // Evicted, not handled: Gmail still has it, so it must be admissible
        // again rather than suppressed as if the user had dealt with it.
        XCTAssertNil(store.item(id: ReviewItemIdentity.id(accountID: account.id, header: oldest)))
        XCTAssertTrue(try store.admit(header: oldest, account: account))
    }

    @MainActor
    func testALongConversationGivesUpContextBeforeItsRepresentative() throws {
        let store = makeStore()
        let account = makeAccount()

        // One oversized conversation, then enough separate mail to overflow.
        for uid in 1...200 {
            _ = try store.admit(header: makeHeader(uid: uid, gmThreadId: "long"), account: account)
        }
        let representative = ReviewItemIdentity.id(
            accountID: account.id,
            header: makeHeader(uid: 1, gmThreadId: "long")
        )
        for uid in 1000...1400 {
            _ = try store.admit(header: makeHeader(uid: uid, gmThreadId: "T\(uid)"), account: account)
        }

        XCTAssertEqual(
            store.retainedMessageCount(accountID: account.id),
            ReviewQueueBudget.retainedMessagesPerAccount
        )
        XCTAssertNotNil(store.item(id: representative), "the conversation keeps its representative")
    }

    @MainActor
    func testBulkActionsReachRetainedMessagesBeyondTheVisibleRows() throws {
        let store = makeStore()
        let account = makeAccount()
        let conversations = ReviewQueueBudget.shownConversationsPerAccount + 15

        for uid in 1...conversations {
            _ = try store.admit(header: makeHeader(uid: uid, gmThreadId: "T\(uid)"), account: account)
        }

        XCTAssertEqual(store.shownItems.count, ReviewQueueBudget.shownConversationsPerAccount)
        // Dismiss All clears the retained store, not just what was on screen.
        XCTAssertEqual(try store.dismissAll(), conversations)
        XCTAssertEqual(store.retainedMessageCount(accountID: account.id), 0)
    }

    // MARK: - Helpers

    @MainActor
    private func makeStore() -> ReviewQueue {
        ReviewQueue(
            persistence: HandledHistory(
                userDefaults: TestDefaults.make()
            )
        )
    }

    private func makeAccount(
        id: String = "66666666-6666-6666-6666-666666666666",
        email: String = "account@example.com"
    ) -> MailAccount {
        ReviewQueueFixture.makeAccount(id: id, email: email)
    }

    private func makeHeader(uid: Int, gmThreadId: String? = nil) -> MessageHeader {
        MessageHeader(
            uid: uid,
            mailboxName: "INBOX",
            from: "sender@example.com",
            subject: "Subject \(uid)",
            date: "",
            gmThreadId: gmThreadId,
            gmMessageId: "msg-\(uid)",
            uidValidity: 1,
            serverReceivedAt: Date(timeIntervalSince1970: TimeInterval(uid) * 60)
        )
    }
}
