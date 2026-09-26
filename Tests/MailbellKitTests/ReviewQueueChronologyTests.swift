import MailbellTestSupport
import XCTest

@testable import MailbellKit

/// Queue order must follow Gmail's ordinary inbox chronology: newest server
/// receipt first. Local admission time is not a stand-in — a backlog fetched
/// after a reconnect arrives in whatever order the server answered.
final class ReviewQueueChronologyTests: XCTestCase {
    @MainActor
    func testOrdersGroupsByNewestServerReceiptRatherThanAdmissionTime() throws {
        let store = makeStore()
        let account = makeAccount()

        // Admitted first, but the server received it last.
        XCTAssertTrue(
            try store.admit(
                header: makeHeader(uid: 1, gmMessageId: "1", serverReceivedAt: date("2026-06-02T12:00:00Z")),
                account: account
            ))
        XCTAssertTrue(
            try store.admit(
                header: makeHeader(uid: 2, gmMessageId: "2", serverReceivedAt: date("2026-06-02T15:00:00Z")),
                account: account
            ))

        XCTAssertEqual(store.shownItems.map(\.imapIdentity?.uid), [2, 1])
    }

    @MainActor
    func testGroupTakesTheReceiptTimeOfItsNewestPendingMember() throws {
        let store = makeStore()
        let account = makeAccount()

        // A thread whose first message is old but whose reply is the newest mail.
        XCTAssertTrue(
            try store.admit(
                header: makeHeader(
                    uid: 1,
                    gmMessageId: "1",
                    gmThreadId: "T",
                    serverReceivedAt: date("2026-06-02T09:00:00Z")
                ),
                account: account
            ))
        XCTAssertTrue(
            try store.admit(
                header: makeHeader(uid: 3, gmMessageId: "3", serverReceivedAt: date("2026-06-02T12:00:00Z")),
                account: account
            ))
        XCTAssertTrue(
            try store.admit(
                header: makeHeader(
                    uid: 2,
                    gmMessageId: "2",
                    gmThreadId: "T",
                    serverReceivedAt: date("2026-06-02T15:00:00Z")
                ),
                account: account
            ))

        // The thread leads on its reply's receipt time, but still shows the
        // first-admitted member as its representative.
        XCTAssertEqual(store.shownItems.count, 2)
        XCTAssertEqual(store.shownItems.first?.imapIdentity?.uid, 1)
        XCTAssertEqual(store.shownItems.last?.imapIdentity?.uid, 3)
    }

    @MainActor
    func testUndatedGroupsFollowDatedGroupsInAdmissionOrder() throws {
        let store = makeStore()
        let account = makeAccount()

        XCTAssertTrue(
            try store.admit(
                header: makeHeader(uid: 1, gmMessageId: "1", serverReceivedAt: nil),
                account: account
            ))
        XCTAssertTrue(
            try store.admit(
                header: makeHeader(uid: 2, gmMessageId: "2", serverReceivedAt: nil),
                account: account
            ))
        XCTAssertTrue(
            try store.admit(
                header: makeHeader(uid: 3, gmMessageId: "3", serverReceivedAt: date("2026-06-02T09:00:00Z")),
                account: account
            ))

        XCTAssertEqual(store.shownItems.map(\.imapIdentity?.uid), [3, 1, 2])
    }

    // MARK: - Helpers

    private func date(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: iso) else {
            XCTFail("invalid fixture date \(iso)")
            return Date(timeIntervalSince1970: 0)
        }
        return date
    }

    @MainActor
    private func makeStore() -> ReviewQueue {
        ReviewQueue(
            persistence: HandledHistory(
                userDefaults: TestDefaults.make()
            )
        )
    }

    private func makeAccount() -> MailAccount {
        ReviewQueueFixture.makeAccount(id: "11111111-1111-1111-1111-111111111111")
    }

    private func makeHeader(
        uid: Int,
        gmMessageId: String,
        gmThreadId: String? = nil,
        serverReceivedAt: Date?
    ) -> MessageHeader {
        MessageHeader(
            uid: uid,
            from: "Sender <sender@example.com>",
            subject: "Subject \(uid)",
            date: "Tue, 02 Jun 2026 12:00:00 +0000",
            gmThreadId: gmThreadId,
            gmMessageId: gmMessageId,
            uidValidity: 1,
            serverReceivedAt: serverReceivedAt
        )
    }
}
