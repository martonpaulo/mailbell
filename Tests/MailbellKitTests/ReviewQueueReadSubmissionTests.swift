import MailbellTestSupport
import XCTest

@testable import MailbellKit

/// Marking as read awaits the network. A reply can join the same thread while
/// that request is in flight, and the server was never asked about it — so it
/// must not be recorded as read when the request completes.
final class ReviewQueueReadSubmissionTests: XCTestCase {
    @MainActor
    func testAMemberThatJoinsDuringTheRequestStaysPending() throws {
        let store = makeStore()
        let account = makeAccount()
        let first = makeHeader(uid: 1, gmMessageId: "A", gmThreadId: "T")
        XCTAssertTrue(try store.admit(header: first, account: account))

        // Captured before the round trip, as the action does.
        let submission = store.readSubmission(
            containing: ReviewItemIdentity.id(accountID: account.id, header: first)
        )
        XCTAssertEqual(submission.identities.count, 1)

        // A reply arrives while the request is suspended.
        let late = makeHeader(uid: 2, gmMessageId: "B", gmThreadId: "T")
        XCTAssertTrue(try store.admit(header: late, account: account))

        try store.markRead(submission: submission)

        XCTAssertEqual(store.shownItems.count, 1, "the late reply must survive")
        XCTAssertEqual(store.shownItems.first?.imapIdentity?.uid, 2)
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
            containing: ReviewItemIdentity.id(accountID: account.id, header: first)
        )
        XCTAssertEqual(submission.itemIDs.count, 2, "both members go to the server")

        try store.markRead(submission: submission)

        XCTAssertTrue(store.shownItems.isEmpty)
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
        XCTAssertEqual(store.shownItems.count, 1)
    }

    @MainActor
    func testBatchCaptureMatchesCapturingEachGroupSeparately() throws {
        let store = makeStore()
        let account = makeAccount()
        for uid in 1...6 {
            let thread = uid % 2 == 0 ? "even" : "odd"
            XCTAssertTrue(
                try store.admit(
                    header: makeHeader(uid: uid, gmMessageId: "M\(uid)", gmThreadId: thread),
                    account: account
                ))
        }
        let ids = store.shownItems.map(\.id)

        let batched = store.readSubmissions(containing: ids)
        let individually = ids.map { store.readSubmission(containing: $0) }

        XCTAssertEqual(batched.map { Set($0.itemIDs) }, individually.map { Set($0.itemIDs) })
        XCTAssertEqual(batched.map { Set($0.identities) }, individually.map { Set($0.identities) })
    }

    @MainActor
    func testBatchCompletionFinalizesEveryCapturedGroupAndNothingElse() throws {
        let store = makeStore()
        let account = makeAccount()
        for uid in 1...4 {
            XCTAssertTrue(
                try store.admit(
                    header: makeHeader(uid: uid, gmMessageId: "M\(uid)"),
                    account: account
                ))
        }
        let capturedIDs = Array(store.shownItems.map(\.id).prefix(3))
        let survivorID = store.shownItems.map(\.id).last

        try store.markRead(submissions: store.readSubmissions(containing: capturedIDs))

        XCTAssertEqual(store.shownItems.map(\.id), [survivorID].compactMap { $0 })
        // Recorded as handled, not merely removed from the queue: a handled
        // message is refused on re-admission.
        for uid in 1...4 {
            let header = makeHeader(uid: uid, gmMessageId: "M\(uid)")
            let id = ReviewItemIdentity.id(accountID: account.id, header: header)
            guard capturedIDs.contains(id) else { continue }
            XCTAssertFalse(try store.admit(header: header, account: account), "uid \(uid) was marked read")
        }
    }

    @MainActor
    func testBatchCompletionWithNothingCapturedChangesNothing() throws {
        let store = makeStore()
        let account = makeAccount()
        XCTAssertTrue(try store.admit(header: makeHeader(uid: 1, gmMessageId: "A"), account: account))

        try store.markRead(submissions: [])
        try store.markRead(submissions: [ReadSubmission(itemIDs: [], identities: [])])

        XCTAssertEqual(store.shownItems.count, 1)
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

    private func makeAccount() -> MailAccount {
        ReviewQueueFixture.makeAccount(id: "44444444-4444-4444-4444-444444444444")
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
