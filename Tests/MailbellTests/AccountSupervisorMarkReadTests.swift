@testable import mailbell
import XCTest

final class AccountSupervisorMarkReadTests: XCTestCase {
    @MainActor
    func testMarkAsReadRemovesEmailFromStoreAfterServerSuccess() async throws {
        var markedAccounts: [UUID] = []
        var markedIdentities: [IMAPMessageIdentity] = []
        let (supervisor, account) = makeSupervisor(emailReadMarker: { account, _, identity in
            markedAccounts.append(account.id)
            markedIdentities.append(identity)
        })
        let header = makeHeader(uid: 42, mailboxName: "INBOX", gmMessageId: "mark-read")

        let didAdmit = await supervisor.monitor(account.id, shouldNotify: header)
        XCTAssertTrue(didAdmit)
        let item = try XCTUnwrap(supervisor.emailStoreItems.first)

        await supervisor.markEmailAsRead(id: item.id)

        XCTAssertEqual(markedAccounts, [account.id])
        XCTAssertEqual(markedIdentities, [IMAPMessageIdentity(uid: 42, mailboxName: "INBOX")])
        XCTAssertTrue(supervisor.emailStoreItems.isEmpty)
        let didReadmit = await supervisor.monitor(account.id, shouldNotify: header)
        XCTAssertFalse(didReadmit)
    }

    @MainActor
    func testMarkAsReadFailureKeepsEmailInStore() async throws {
        let (supervisor, account) = makeSupervisor(emailReadMarker: { _, _, _ in
            throw MarkReadTestError.failed
        })
        let header = makeHeader(uid: 43, gmMessageId: "mark-read-failure")

        let didAdmit = await supervisor.monitor(account.id, shouldNotify: header)
        XCTAssertTrue(didAdmit)
        let item = try XCTUnwrap(supervisor.emailStoreItems.first)

        await supervisor.markEmailAsRead(id: item.id)

        XCTAssertEqual(supervisor.emailStoreItems.map(\.id), [item.id])
    }

    @MainActor
    func testMarkAsReadSkipsLegacyPendingItemWithoutUID() async throws {
        var didCallMarker = false
        let (supervisor, account) = makeSupervisor(emailReadMarker: { _, _, _ in
            didCallMarker = true
        })
        let header = makeHeader(uid: 0, gmMessageId: "legacy-without-uid")

        let didAdmit = await supervisor.monitor(account.id, shouldNotify: header)
        XCTAssertTrue(didAdmit)
        let item = try XCTUnwrap(supervisor.emailStoreItems.first)
        XCTAssertFalse(item.canMarkAsRead)

        await supervisor.markEmailAsRead(id: item.id)

        XCTAssertFalse(didCallMarker)
        XCTAssertEqual(supervisor.emailStoreItems.map(\.id), [item.id])
    }

    @MainActor
    private func makeSupervisor(
        emailReadMarker: @escaping EmailReadMarker
    ) -> (AccountSupervisor, MailAccount) {
        let account = MailAccount(providerID: .gmail, email: "test@example.com")
        let suiteName = "mailbell.AccountSupervisorMarkReadTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = AccountStore(userDefaults: defaults)
        store.saveAccounts([account])
        let emailStore = EmailStore(persistence: EmailStorePersistence(userDefaults: defaults))
        let supervisor = AccountSupervisor(
            configProvider: {
                OAuthConfig(
                    clientID: "dummy-local-client-id.apps.googleusercontent.com",
                    clientSecret: "dummy-local-client-secret"
                )
            },
            accountStore: store,
            emailStore: emailStore,
            monitorFactory: { account, _, includeSpam in
                MarkReadSpyMonitor(account: account, includeSpam: includeSpam)
            },
            emailReadMarker: emailReadMarker
        )
        return (supervisor, account)
    }

    private func makeHeader(
        uid: Int,
        mailboxName: String? = nil,
        gmMessageId: String
    ) -> MessageHeader {
        MessageHeader(
            uid: uid,
            mailboxName: mailboxName,
            from: "sender@example.com",
            subject: "Subject",
            date: "",
            gmThreadId: nil,
            gmMessageId: gmMessageId
        )
    }
}

private final class MarkReadSpyMonitor: AccountMonitoring {
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

    func start() {}

    func stop(clearSession _: Bool) {}

    func forceReconnect() {}

    func refreshNow() {}

    func setIncludeSpam(_ includeSpam: Bool) {
        self.includeSpam = includeSpam
    }
}

private enum MarkReadTestError: Error {
    case failed
}
