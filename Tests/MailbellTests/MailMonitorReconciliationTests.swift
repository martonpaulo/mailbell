@testable import mailbell
import Foundation
import XCTest

final class MailMonitorReconciliationTests: XCTestCase {
    @MainActor
    func testMailboxChangeReconcilesProviderUnreadAndRemovesExternallyReadPending() async throws {
        let account = MailAccount(providerID: .gmail, email: "account@example.com")
        let store = makeStore()
        let pendingHeader = makeHeader(uid: 1, gmMessageId: "externally-read")
        XCTAssertTrue(store.admit(header: pendingHeader, account: account))

        let connection = ScriptedMonitorConnection(lines: [
            "A0001 OK SELECT completed",
            "* SEARCH",
            "A0002 OK SEARCH completed",
            "A0003 OK SELECT completed",
            "* SEARCH",
            "A0004 OK SEARCH completed",
            "A0005 OK SELECT completed"
        ])
        let (monitor, delegate) = makeMonitor(account: account, store: store)
        _ = delegate
        let client = IMAPClient(connection: connection)

        try await monitor.handleIdleCycle(
            event: .mailboxChanged,
            client: client,
            mailboxes: [MonitoredMailbox(role: .inbox, name: "INBOX")]
        )

        XCTAssertTrue(store.items.isEmpty)
        XCTAssertEqual(
            connection.sentLines,
            [
                #"A0001 SELECT "INBOX""#,
                "A0002 UID SEARCH UID 1:* UNSEEN",
                #"A0003 SELECT "INBOX""#,
                "A0004 UID SEARCH UNSEEN",
                #"A0005 SELECT "INBOX""#
            ]
        )
    }

    @MainActor
    func testUnreadReconciliationFetchesOnlyUnknownUnreadUIDs() async throws {
        let account = MailAccount(providerID: .gmail, email: "account@example.com")
        let store = makeStore()
        let pendingHeader = makeHeader(uid: 1, gmMessageId: "known-unread")
        XCTAssertTrue(store.admit(header: pendingHeader, account: account))

        let connection = ScriptedMonitorConnection(lines: [
            "A0001 OK SELECT completed",
            "* SEARCH",
            "A0002 OK SEARCH completed",
            "A0003 OK SELECT completed",
            "* SEARCH 1 2 3",
            "A0004 OK SEARCH completed",
            "A0005 OK FETCH completed",
            "A0006 OK SELECT completed"
        ])
        let (monitor, delegate) = makeMonitor(account: account, store: store)
        _ = delegate
        let client = IMAPClient(connection: connection)

        try await monitor.handleIdleCycle(
            event: .mailboxChanged,
            client: client,
            mailboxes: [MonitoredMailbox(role: .inbox, name: "INBOX")]
        )

        XCTAssertEqual(store.pendingUIDs(accountID: account.id, mailbox: .inbox), Set([1]))
        XCTAssertEqual(
            connection.sentLines,
            [
                #"A0001 SELECT "INBOX""#,
                "A0002 UID SEARCH UID 1:* UNSEEN",
                #"A0003 SELECT "INBOX""#,
                "A0004 UID SEARCH UNSEEN",
                "A0005 UID FETCH 2:3 (UID X-GM-MSGID X-GM-THRID BODY.PEEK[HEADER.FIELDS (FROM SUBJECT DATE MESSAGE-ID)])",
                #"A0006 SELECT "INBOX""#
            ]
        )
    }

    @MainActor
    func testIdleReconciliationFailureDoesNotClearPending() async throws {
        let account = MailAccount(providerID: .gmail, email: "account@example.com")
        let store = makeStore()
        let pendingHeader = makeHeader(uid: 1, gmMessageId: "still-pending")
        XCTAssertTrue(store.admit(header: pendingHeader, account: account))

        let connection = ScriptedMonitorConnection(lines: [
            "A0001 OK SELECT completed",
            "A0002 BAD temporary failure"
        ])
        let (monitor, delegate) = makeMonitor(account: account, store: store)
        _ = delegate
        let client = IMAPClient(connection: connection)

        do {
            try await monitor.handleIdleCycle(
                event: .timedOut,
                client: client,
                mailboxes: [MonitoredMailbox(role: .inbox, name: "INBOX")]
            )
            XCTFail("Expected IMAP failure.")
        } catch {
            XCTAssertEqual(store.items.map(\.id), [EmailStoreIdentity.id(accountID: account.id, header: pendingHeader)])
        }
    }

    @MainActor
    private func makeMonitor(account: MailAccount, store: EmailStore) -> (MailMonitor, ReconciliationDelegate) {
        let monitor = MailMonitor(
            account: account,
            config: OAuthConfig(
                clientID: "dummy-local-client-id.apps.googleusercontent.com",
                clientSecret: "dummy-local-client-secret"
            )
        )
        let delegate = ReconciliationDelegate(account: account, store: store)
        monitor.delegate = delegate
        return (monitor, delegate)
    }

    @MainActor
    private func makeStore() -> EmailStore {
        let suiteName = "mailbell.MailMonitorReconciliationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return EmailStore(persistence: EmailStorePersistence(userDefaults: defaults))
    }

    private func makeHeader(uid: Int, gmMessageId: String) -> MessageHeader {
        MessageHeader(
            uid: uid,
            mailboxName: "INBOX",
            from: "sender@example.com",
            subject: "Subject",
            date: "",
            gmThreadId: nil,
            gmMessageId: gmMessageId
        )
    }
}

private final class ReconciliationDelegate: MailMonitorDelegate {
    private let account: MailAccount
    private let store: EmailStore

    init(account: MailAccount, store: EmailStore) {
        self.account = account
        self.store = store
    }

    func monitor(_ accountID: UUID, pendingUIDsFor mailbox: MessageMailbox) async -> Set<Int> {
        guard accountID == account.id else { return [] }
        return await store.pendingUIDs(accountID: account.id, mailbox: mailbox)
    }

    func monitor(
        _ accountID: UUID,
        didReconcileUnread snapshots: [MailboxUnreadSnapshot],
        fetchedHeaders: [MessageHeader]
    ) async {
        guard accountID == account.id else { return }
        _ = await store.reconcileUnread(snapshots: snapshots, fetchedHeaders: fetchedHeaders, account: account)
    }

    func monitor(_ accountID: UUID, shouldNotify headers: [MessageHeader]) async -> Set<IMAPMessageIdentity> {
        guard accountID == account.id else { return [] }
        var admittedIdentities = Set<IMAPMessageIdentity>()
        for header in headers {
            if await store.admit(header: header, account: account),
               let identity = header.imapIdentity {
                admittedIdentities.insert(identity)
            }
        }
        return admittedIdentities
    }

    func monitor(_: UUID, didChangeStatus _: MonitorStatus, error _: String?) {}

    func monitor(_: UUID, didNotify _: MessageHeader, result _: NotificationPostResult) {}
}

private final class ScriptedMonitorConnection: IMAPClientTransport, @unchecked Sendable {
    private var lines: [String]
    private(set) var sentLines: [String] = []

    init(lines: [String]) {
        self.lines = lines
    }

    func connect() async throws {}

    func cancel() {}

    func send(_ line: String) async throws {
        sentLines.append(line)
    }

    func sendRaw(_ text: String) async throws {
        sentLines.append(text)
    }

    func readLine() async throws -> String {
        guard !lines.isEmpty else { throw ScriptedMonitorConnectionError.missingLine }
        return lines.removeFirst()
    }

    func readBytes(_: Int) async throws -> Data {
        Data()
    }
}

private enum ScriptedMonitorConnectionError: Error {
    case missingLine
}
