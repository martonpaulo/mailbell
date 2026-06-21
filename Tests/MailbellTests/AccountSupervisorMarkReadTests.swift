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

        let didAdmit = await admit(header, into: supervisor, account: account)
        XCTAssertTrue(didAdmit)
        let item = try XCTUnwrap(supervisor.emailStoreItems.first)

        await supervisor.markEmailAsRead(id: item.id)

        XCTAssertEqual(markedAccounts, [account.id])
        XCTAssertEqual(markedIdentities, [IMAPMessageIdentity(uid: 42, mailboxName: "INBOX")])
        XCTAssertTrue(supervisor.emailStoreItems.isEmpty)
        let didReadmit = await supervisor.monitor(account.id, shouldNotify: [header])
        XCTAssertTrue(didReadmit.isEmpty)
    }

    @MainActor
    func testMarkAsReadMarksEveryKnownMessageInThreadGroup() async throws {
        var markedIdentities: [IMAPMessageIdentity] = []
        let (supervisor, account) = makeSupervisor(emailReadMarker: { _, _, identity in
            markedIdentities.append(identity)
        })
        let firstHeader = makeHeader(uid: 41, mailboxName: "INBOX", gmMessageId: "message-1", gmThreadId: "thread-1")
        let secondHeader = makeHeader(uid: 42, mailboxName: "INBOX", gmMessageId: "message-2", gmThreadId: "thread-1")

        let didAdmitFirst = await admit(firstHeader, into: supervisor, account: account)
        let didAdmitSecond = await admit(secondHeader, into: supervisor, account: account)
        XCTAssertTrue(didAdmitFirst)
        XCTAssertTrue(didAdmitSecond)
        let item = try XCTUnwrap(supervisor.emailStoreItems.first)

        await supervisor.markEmailAsRead(id: item.id)

        XCTAssertEqual(
            Set(markedIdentities),
            Set([
                IMAPMessageIdentity(uid: 41, mailboxName: "INBOX"),
                IMAPMessageIdentity(uid: 42, mailboxName: "INBOX")
            ])
        )
        XCTAssertTrue(supervisor.emailStoreItems.isEmpty)
    }

    @MainActor
    func testMarkAsReadFailureKeepsEmailInStore() async throws {
        let (supervisor, account) = makeSupervisor(emailReadMarker: { _, _, _ in
            throw MarkReadTestError.failed
        })
        let header = makeHeader(uid: 43, gmMessageId: "mark-read-failure")

        let didAdmit = await admit(header, into: supervisor, account: account)
        XCTAssertTrue(didAdmit)
        let item = try XCTUnwrap(supervisor.emailStoreItems.first)

        await supervisor.markEmailAsRead(id: item.id)

        XCTAssertEqual(supervisor.emailStoreItems.map(\.id), [item.id])
    }

    @MainActor
    func testMarkAsReadPersistenceFailureKeepsEmailInStoreAndSurfacesError() async throws {
        let defaults = makeDefaults()
        var shouldFail = false
        let emailStore = EmailStore(
            persistence: EmailStorePersistence(
                userDefaults: defaults,
                saveData: { data, key in
                    if shouldFail {
                        throw EmailStorePersistence.PersistenceError.saveFailed("disk full")
                    }
                    defaults.set(data, forKey: key)
                }
            )
        )
        let (supervisor, account) = makeSupervisor(
            emailStore: emailStore,
            emailReadMarker: { _, _, _ in }
        )
        let header = makeHeader(uid: 44, mailboxName: "INBOX", gmMessageId: "mark-read-persistence-failure")

        let didAdmit = await admit(header, into: supervisor, account: account)
        XCTAssertTrue(didAdmit)
        let item = try XCTUnwrap(supervisor.emailStoreItems.first)
        shouldFail = true

        await supervisor.markEmailAsRead(id: item.id)

        XCTAssertEqual(supervisor.emailStoreItems.map(\.id), [item.id])
        XCTAssertEqual(
            supervisor.accountStates.first?.lastError,
            "Could not save handled-message history: disk full"
        )
    }

    @MainActor
    func testMarkAsReadSkipsLegacyPendingItemWithoutUID() async throws {
        var didCallMarker = false
        let (supervisor, account) = makeSupervisor(emailReadMarker: { _, _, _ in
            didCallMarker = true
        })
        let header = makeHeader(uid: 0, gmMessageId: "legacy-without-uid")

        _ = await supervisor.monitor(account.id, shouldNotify: [header])
        let didAdmit = supervisor.emailStoreItems.contains {
            $0.id == EmailStoreIdentity.id(accountID: account.id, header: header)
        }
        XCTAssertTrue(didAdmit)
        let item = try XCTUnwrap(supervisor.emailStoreItems.first)
        XCTAssertFalse(item.canMarkAsRead)

        await supervisor.markEmailAsRead(id: item.id)

        XCTAssertFalse(didCallMarker)
        XCTAssertEqual(supervisor.emailStoreItems.map(\.id), [item.id])
    }

    @MainActor
    private func makeSupervisor(
        emailStore: EmailStore? = nil,
        emailReadMarker: @escaping EmailReadMarker
    ) -> (AccountSupervisor, MailAccount) {
        let account = MailAccount(providerID: .gmail, email: "test@example.com")
        let suiteName = "mailbell.AccountSupervisorMarkReadTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = AccountStore(userDefaults: defaults)
        do {
            try store.saveAccounts([account])
        } catch {
            XCTFail("Could not seed account store: \(error)")
        }
        let emailStore = emailStore ?? EmailStore(persistence: EmailStorePersistence(userDefaults: defaults))
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

    private func makeDefaults() -> UserDefaults {
        let suiteName = "mailbell.AccountSupervisorMarkReadTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func makeHeader(
        uid: Int,
        mailboxName: String? = nil,
        gmMessageId: String,
        gmThreadId: String? = nil
    ) -> MessageHeader {
        MessageHeader(
            uid: uid,
            mailboxName: mailboxName,
            from: "sender@example.com",
            subject: "Subject",
            date: "",
            gmThreadId: gmThreadId,
            gmMessageId: gmMessageId
        )
    }

    @MainActor
    private func admit(
        _ header: MessageHeader,
        into supervisor: AccountSupervisor,
        account: MailAccount
    ) async -> Bool {
        guard let identity = header.imapIdentity else {
            _ = await supervisor.monitor(account.id, shouldNotify: [header])
            let id = EmailStoreIdentity.id(accountID: account.id, header: header)
            return supervisor.emailStoreItems.contains { $0.id == id }
        }
        let admittedIdentities = await supervisor.monitor(account.id, shouldNotify: [header])
        return admittedIdentities.contains(identity)
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

    func hasStoredSession() throws -> Bool {
        hasSession
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
