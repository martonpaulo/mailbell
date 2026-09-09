@testable import mailbell
import XCTest

/// RFC 3501 identifies a message by mailbox name, UIDVALIDITY and UID together.
/// A UID alone is not an identity: after the generation changes, the server may
/// hand the same number to a different message, so a read action prepared under
/// the old generation would mark the wrong mail.
final class IMAPMailboxGenerationTests: XCTestCase {
    func testMarkAsReadRefusesToStoreAgainstANewerMailboxGeneration() async throws {
        let connection = ScriptedIMAPConnection(lines: [
            "* 5 EXISTS",
            "* OK [UIDVALIDITY 2] UIDs valid",
            "* OK [UIDNEXT 90] Predicted next UID",
            "A0001 OK [READ-WRITE] SELECT completed"
        ])
        let client = IMAPClient(connection: connection)

        _ = try await client.selectMailbox("INBOX")

        do {
            // The pending item was captured under generation 1.
            try await client.markAsRead(uids: [42], requiringUIDValidity: 1)
            XCTFail("expected the stale generation to be rejected")
        } catch let error as IMAPClient.IMAPError {
            guard case let .staleMailboxGeneration(expected, actual) = error else {
                return XCTFail("unexpected error \(error)")
            }
            XCTAssertEqual(expected, 1)
            XCTAssertEqual(actual, 2)
        }

        // The decisive assertion: no STORE reached the server.
        XCTAssertFalse(connection.sentLines.contains { $0.contains("STORE") })
    }

    func testMarkAsReadStoresWhenTheGenerationStillMatches() async throws {
        let connection = ScriptedIMAPConnection(lines: [
            "* 5 EXISTS",
            "* OK [UIDVALIDITY 1] UIDs valid",
            "* OK [UIDNEXT 90] Predicted next UID",
            "A0001 OK [READ-WRITE] SELECT completed",
            "A0002 OK STORE completed"
        ])
        let client = IMAPClient(connection: connection)

        _ = try await client.selectMailbox("INBOX")
        try await client.markAsRead(uids: [42], requiringUIDValidity: 1)

        XCTAssertEqual(connection.sentLines.last, "A0002 UID STORE 42 +FLAGS.SILENT (\\Seen)")
    }

    func testMarkAsReadRefusesWhenNoMailboxHasBeenSelected() async throws {
        let connection = ScriptedIMAPConnection(lines: ["A0001 OK STORE completed"])
        let client = IMAPClient(connection: connection)

        do {
            try await client.markAsRead(uids: [42], requiringUIDValidity: 1)
            XCTFail("expected a refusal without a selected mailbox")
        } catch let error as IMAPClient.IMAPError {
            guard case .staleMailboxGeneration = error else {
                return XCTFail("unexpected error \(error)")
            }
        }

        XCTAssertTrue(connection.sentLines.isEmpty)
    }

    func testIdentityCarriesTheMailboxGeneration() {
        let identity = IMAPMessageIdentity(uid: 42, mailboxName: "INBOX", uidValidity: 1)

        XCTAssertEqual(identity?.uidValidity, 1)
        // A generation of zero is not a generation: RFC 3501 requires nonzero.
        XCTAssertNil(IMAPMessageIdentity(uid: 42, mailboxName: "INBOX", uidValidity: 0))
    }

    func testIdentitiesDifferAcrossGenerationsForTheSameUID() {
        let old = IMAPMessageIdentity(uid: 42, mailboxName: "INBOX", uidValidity: 1)
        let new = IMAPMessageIdentity(uid: 42, mailboxName: "INBOX", uidValidity: 2)

        XCTAssertNotEqual(old, new)
    }

    // MARK: - Pending items across a generation change

    @MainActor
    func testReconciliationDropsPendingItemsFromAnEarlierGeneration() throws {
        let store = makeStore()
        let account = makeAccount()
        let old = makeHeader(uid: 42, gmMessageId: "A", uidValidity: 1)
        XCTAssertTrue(try store.admit(header: old, account: account))

        // The mailbox is rebuilt and UID 42 now belongs to a different message.
        _ = try store.reconcileUnread(
            snapshots: [MailboxUnreadSnapshot(
                mailbox: .inbox,
                mailboxName: "INBOX",
                uidValidity: 2,
                unreadUIDs: [42]
            )],
            fetchedHeaders: [],
            account: account
        )

        XCTAssertTrue(store.items.isEmpty, "a stale identity must not survive as an actionable item")
    }

    @MainActor
    func testReconciliationKeepsPendingItemsWhenTheGenerationIsUnchanged() throws {
        let store = makeStore()
        let account = makeAccount()
        XCTAssertTrue(try store.admit(header: makeHeader(uid: 42, gmMessageId: "A", uidValidity: 1), account: account))

        _ = try store.reconcileUnread(
            snapshots: [MailboxUnreadSnapshot(
                mailbox: .inbox,
                mailboxName: "INBOX",
                uidValidity: 1,
                unreadUIDs: [42]
            )],
            fetchedHeaders: [],
            account: account
        )

        XCTAssertEqual(store.items.count, 1)
    }

    @MainActor
    func testPendingUIDsAreScopedToTheirGeneration() throws {
        let store = makeStore()
        let account = makeAccount()
        XCTAssertTrue(try store.admit(header: makeHeader(uid: 42, gmMessageId: "A", uidValidity: 1), account: account))

        // Under the new generation UID 42 is unknown, so it must not be
        // suppressed from the unknown-message fetch.
        XCTAssertEqual(store.pendingUIDs(accountID: account.id, mailbox: .inbox, uidValidity: 1), [42])
        XCTAssertTrue(store.pendingUIDs(accountID: account.id, mailbox: .inbox, uidValidity: 2).isEmpty)
    }

    @MainActor
    private func makeStore() -> EmailStore {
        EmailStore(
            persistence: EmailStorePersistence(
                userDefaults: UserDefaults(suiteName: "mailbell.tests.generation.\(UUID().uuidString)")!
            )
        )
    }

    private func makeAccount() -> MailAccount {
        MailAccount(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            providerID: .gmail,
            email: "account@example.com"
        )
    }

    private func makeHeader(uid: Int, gmMessageId: String, uidValidity: Int) -> MessageHeader {
        MessageHeader(
            uid: uid,
            mailboxName: "INBOX",
            from: "sender@example.com",
            subject: "Subject",
            date: "",
            gmThreadId: nil,
            gmMessageId: gmMessageId,
            uidValidity: uidValidity
        )
    }
}
