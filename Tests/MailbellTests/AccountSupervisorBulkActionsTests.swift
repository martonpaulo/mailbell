@testable import mailbell
import XCTest

final class AccountSupervisorBulkActionsTests: XCTestCase {
    @MainActor
    func testMarkAllAsReadMarksEveryPendingIdentityInOneServerCall() async {
        var callCount = 0
        var markedIdentities: [IMAPMessageIdentity] = []
        let (supervisor, account) = makeSupervisor(emailReadMarker: { _, _, identities in
            callCount += 1
            markedIdentities.append(contentsOf: identities)
        })
        _ = await supervisor.monitor(account.id, shouldNotify: [
            makeHeader(uid: 10, gmMessageId: "one"),
            makeHeader(uid: 11, gmMessageId: "two"),
            makeHeader(uid: 12, gmMessageId: "three")
        ])
        XCTAssertEqual(supervisor.emailStoreItems.count, 3)

        let result = await supervisor.markAllEmailsAsRead()

        XCTAssertEqual(result, .markedAllAsRead(count: 3))
        XCTAssertEqual(callCount, 1, "one authenticated IMAP session per account")
        XCTAssertEqual(
            Set(markedIdentities),
            Set([
                IMAPMessageIdentity(uid: 10, mailboxName: "INBOX"),
                IMAPMessageIdentity(uid: 11, mailboxName: "INBOX"),
                IMAPMessageIdentity(uid: 12, mailboxName: "INBOX")
            ])
        )
        XCTAssertTrue(supervisor.emailStoreItems.isEmpty)
    }

    @MainActor
    func testMarkAllAsReadKeepsItemsWhenTheServerCallFails() async {
        let (supervisor, account) = makeSupervisor(emailReadMarker: { _, _, _ in
            throw BulkActionTestError.failed
        })
        _ = await supervisor.monitor(account.id, shouldNotify: [
            makeHeader(uid: 20, gmMessageId: "one"),
            makeHeader(uid: 21, gmMessageId: "two")
        ])

        let result = await supervisor.markAllEmailsAsRead()

        XCTAssertEqual(result, .markAsReadFailed)
        XCTAssertEqual(supervisor.emailStoreItems.count, 2)
    }

    @MainActor
    func testMarkAllAsReadReportsItemsWithoutIMAPIdentityAsFailed() async {
        let (supervisor, account) = makeSupervisor(emailReadMarker: { _, _, _ in })
        _ = await supervisor.monitor(account.id, shouldNotify: [
            makeHeader(uid: 30, gmMessageId: "with-uid"),
            makeHeader(uid: 0, gmMessageId: "legacy-without-uid")
        ])
        XCTAssertEqual(supervisor.emailStoreItems.count, 2)

        let result = await supervisor.markAllEmailsAsRead()

        XCTAssertEqual(result, .partiallyMarkedAsRead(marked: 1, failed: 1))
        XCTAssertEqual(supervisor.emailStoreItems.count, 1)
        XCTAssertFalse(supervisor.canMarkAllAsRead)
    }

    @MainActor
    func testMarkAllAsReadOnAnEmptyStoreReportsNothingPending() async {
        let (supervisor, _) = makeSupervisor(emailReadMarker: { _, _, _ in })

        let result = await supervisor.markAllEmailsAsRead()

        XCTAssertEqual(result, .nothingPending)
    }

    @MainActor
    func testDismissAllClearsEveryItemWithoutTouchingTheServer() async {
        var didCallMarker = false
        let (supervisor, account) = makeSupervisor(emailReadMarker: { _, _, _ in
            didCallMarker = true
        })
        let headers = [
            makeHeader(uid: 40, gmMessageId: "one"),
            makeHeader(uid: 41, gmMessageId: "two")
        ]
        _ = await supervisor.monitor(account.id, shouldNotify: headers)

        let result = supervisor.dismissAllEmails()

        XCTAssertEqual(result, .dismissedAll(count: 2))
        XCTAssertFalse(didCallMarker)
        XCTAssertTrue(supervisor.emailStoreItems.isEmpty)

        let readmitted = await supervisor.monitor(account.id, shouldNotify: headers)
        XCTAssertTrue(readmitted.isEmpty, "dismissed messages must not come back")
    }

    @MainActor
    func testDismissAllCountsAThreadOnce() async {
        let (supervisor, account) = makeSupervisor(emailReadMarker: { _, _, _ in })
        _ = await supervisor.monitor(account.id, shouldNotify: [
            makeHeader(uid: 50, gmMessageId: "message-1", gmThreadId: "thread-1"),
            makeHeader(uid: 51, gmMessageId: "message-2", gmThreadId: "thread-1")
        ])
        XCTAssertEqual(supervisor.emailStoreItems.count, 1)

        XCTAssertEqual(supervisor.dismissAllEmails(), .dismissedAll(count: 1))
    }

    @MainActor
    func testDismissAllOnAnEmptyStoreReportsNothingPending() {
        let (supervisor, _) = makeSupervisor(emailReadMarker: { _, _, _ in })

        XCTAssertEqual(supervisor.dismissAllEmails(), .nothingPending)
    }

    @MainActor
    private func makeSupervisor(
        emailReadMarker: @escaping EmailReadMarker
    ) -> (AccountSupervisor, MailAccount) {
        let account = MailAccount(providerID: .gmail, email: "bulk@example.com")
        let suiteName = "mailbell.AccountSupervisorBulkActionsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = AccountStore(userDefaults: defaults)
        do {
            try store.saveAccounts([account])
        } catch {
            XCTFail("Could not seed account store: \(error)")
        }
        let supervisor = AccountSupervisor(
            configProvider: {
                OAuthConfig(
                    clientID: "dummy-local-client-id.apps.googleusercontent.com",
                    clientSecret: nil
                )
            },
            accountStore: store,
            emailStore: EmailStore(persistence: EmailStorePersistence(userDefaults: defaults)),
            monitorFactory: { account, _, includeSpam in
                BulkActionSpyMonitor(account: account, includeSpam: includeSpam)
            },
            emailReadMarker: emailReadMarker
        )
        return (supervisor, account)
    }

    private func makeHeader(
        uid: Int,
        gmMessageId: String,
        gmThreadId: String? = nil
    ) -> MessageHeader {
        MessageHeader(
            uid: uid,
            mailboxName: "INBOX",
            from: "sender@example.com",
            subject: "Subject \(gmMessageId)",
            date: "",
            gmThreadId: gmThreadId,
            gmMessageId: gmMessageId
        )
    }
}

private final class BulkActionSpyMonitor: AccountMonitoring {
    weak var delegate: MailMonitorDelegate?
    private(set) var account: MailAccount
    let hasSession = false
    private(set) var includeSpam: Bool

    init(account: MailAccount, includeSpam: Bool) {
        self.account = account
        self.includeSpam = includeSpam
    }

    func updateAccount(_ account: MailAccount) {
        self.account = account
    }

    func hasStoredSession() throws -> Bool {
        false
    }

    func start() {}

    func stop(clearSession _: Bool) {}

    func forceReconnect() {}

    func refreshNow() {}

    func setIncludeSpam(_ includeSpam: Bool) {
        self.includeSpam = includeSpam
    }
}

private enum BulkActionTestError: Error {
    case failed
}
