@testable import mailbell
import XCTest

/// Marking as read awaits the network. A reply can join the same thread while
/// that request is in flight, and the server was never asked about it — so it
/// must not be recorded as read when the request completes.
final class EmailStoreReadSubmissionTests: XCTestCase {
    @MainActor
    func testAMemberThatJoinsDuringTheRequestStaysPending() throws {
        let store = makeStore()
        let account = makeAccount()
        let first = makeHeader(uid: 1, gmMessageId: "A", gmThreadId: "T")
        XCTAssertTrue(try store.admit(header: first, account: account))

        // Captured before the round trip, as the action does.
        let submission = store.readSubmission(
            containing: EmailStoreIdentity.id(accountID: account.id, header: first)
        )
        XCTAssertEqual(submission.identities.count, 1)

        // A reply arrives while the request is suspended.
        let late = makeHeader(uid: 2, gmMessageId: "B", gmThreadId: "T")
        XCTAssertTrue(try store.admit(header: late, account: account))

        try store.markRead(submission: submission)

        XCTAssertEqual(store.items.count, 1, "the late reply must survive")
        XCTAssertEqual(store.items.first?.imapIdentity?.uid, 2)
        // And it must still be admissible, i.e. not recorded as handled.
        XCTAssertFalse(try store.admit(header: first, account: account), "A was marked read")
    }

    @MainActor
    func testTheSubmittedMembersAreFinalized() throws {
        let store = makeStore()
        let account = makeAccount()
        let first = makeHeader(uid: 1, gmMessageId: "A", gmThreadId: "T")
        let second = makeHeader(uid: 2, gmMessageId: "B", gmThreadId: "T")
        XCTAssertTrue(try store.admit(header: first, account: account))
        XCTAssertTrue(try store.admit(header: second, account: account))

        let submission = store.readSubmission(
            containing: EmailStoreIdentity.id(accountID: account.id, header: first)
        )
        XCTAssertEqual(submission.itemIDs.count, 2, "both members go to the server")

        try store.markRead(submission: submission)

        XCTAssertTrue(store.items.isEmpty)
        XCTAssertFalse(try store.admit(header: first, account: account))
        XCTAssertFalse(try store.admit(header: second, account: account))
    }

    @MainActor
    func testASubmissionForAnUnknownItemIsEmptyAndFinalizesNothing() throws {
        let store = makeStore()
        let account = makeAccount()
        XCTAssertTrue(try store.admit(header: makeHeader(uid: 1, gmMessageId: "A"), account: account))

        let submission = store.readSubmission(containing: "not-a-pending-id")

        XCTAssertTrue(submission.isEmpty)
        try store.markRead(submission: submission)
        XCTAssertEqual(store.items.count, 1)
    }

    // MARK: - Helpers

    @MainActor
    private func makeStore() -> EmailStore {
        EmailStore(
            persistence: EmailStorePersistence(
                userDefaults: UserDefaults(suiteName: "mailbell.tests.submission.\(UUID().uuidString)")!
            )
        )
    }

    private func makeAccount() -> MailAccount {
        MailAccount(
            id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
            providerID: .gmail,
            email: "account@example.com"
        )
    }

    private func makeHeader(uid: Int, gmMessageId: String, gmThreadId: String? = nil) -> MessageHeader {
        MessageHeader(
            uid: uid,
            mailboxName: "INBOX",
            from: "sender@example.com",
            subject: "Subject",
            date: "",
            gmThreadId: gmThreadId,
            gmMessageId: gmMessageId,
            uidValidity: 1
        )
    }
}
