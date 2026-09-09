@testable import mailbell
import XCTest

/// Shared fixtures for the supervisor suites. One home, so the two files that
/// exercise different halves of the supervisor cannot drift apart.
@MainActor
enum SupervisorFixture {
    static func makeSupervisor(
        configProvider: @escaping () throws -> OAuthConfig = {
            OAuthConfig(
                clientID: "dummy-local-client-id.apps.googleusercontent.com",
                clientSecret: "dummy-local-client-secret"
            )
        },
        account: MailAccount = MailAccount(providerID: .gmail, email: "test@example.com"),
        includeSpam: Bool = false,
        monitorFactory: @escaping AccountMonitorFactory = { account, _, includeSpam in
            SpyMonitor(account: account, hasSession: false, includeSpam: includeSpam)
        },
        webmailOpen: @escaping @MainActor (URL, MailAccount?) async -> WebmailOpenOutcome = { _, _ in .opened },
        signInNeededNotifier: @escaping SignInNeededNotifier = { _ in }
    ) -> (AccountSupervisor, MailAccount) {
        (
            makeSupervisor(
                accounts: [account],
                configProvider: configProvider,
                includeSpam: includeSpam,
                monitorFactory: monitorFactory,
                webmailOpen: webmailOpen,
                signInNeededNotifier: signInNeededNotifier
            ),
            account
        )
    }

    @MainActor
    static func makeSupervisor(
        accounts: [MailAccount],
        configProvider: @escaping () throws -> OAuthConfig = {
            OAuthConfig(
                clientID: "dummy-local-client-id.apps.googleusercontent.com",
                clientSecret: "dummy-local-client-secret"
            )
        },
        includeSpam: Bool = false,
        monitorFactory: @escaping AccountMonitorFactory = { account, _, includeSpam in
            SpyMonitor(account: account, hasSession: false, includeSpam: includeSpam)
        },
        emailStore: EmailStore? = nil,
        webmailOpen: @escaping @MainActor (URL, MailAccount?) async -> WebmailOpenOutcome = { _, _ in .opened },
        signInNeededNotifier: @escaping SignInNeededNotifier = { _ in }
    ) -> AccountSupervisor {
        let suiteName = "mailbell.AccountSupervisorTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = AccountStore(userDefaults: defaults)
        do {
            try store.saveAccounts(accounts)
        } catch {
            XCTFail("Could not seed account store: \(error)")
        }
        let emailStore = emailStore ?? EmailStore(persistence: EmailStorePersistence(userDefaults: defaults))
        return AccountSupervisor(
            configProvider: configProvider,
            accountStore: store,
            emailStore: emailStore,
            includeSpam: includeSpam,
            monitorFactory: monitorFactory,
            webmailOpen: webmailOpen,
            signInNeededNotifier: signInNeededNotifier
        )
    }

    static func makeHeader(
        uid: Int = 1,
        mailbox: MessageMailbox = .inbox,
        subject: String = "Subject",
        gmMessageId: String? = nil,
        gmThreadId: String? = nil
    ) -> MessageHeader {
        MessageHeader(
            uid: uid,
            mailbox: mailbox,
            from: "sender@example.com",
            subject: subject,
            date: "",
            gmThreadId: gmThreadId,
            gmMessageId: gmMessageId,
            uidValidity: 1
        )
    }

    @MainActor
    static func admit(
        _ header: MessageHeader,
        into supervisor: AccountSupervisor,
        account: MailAccount
    ) async -> Bool {
        let admittedIdentities = await supervisor.monitor(account.id, shouldNotify: [header])
        guard let identity = header.imapIdentity else {
            let id = EmailStoreIdentity.id(accountID: account.id, header: header)
            return supervisor.emailStoreItems.contains { $0.id == id }
        }
        return admittedIdentities.contains(identity)
    }

    static func makeSnapshot(
        mailbox: MessageMailbox = .inbox,
        mailboxName: String = "INBOX",
        uids: [Int]
    ) -> MailboxUnreadSnapshot {
        MailboxUnreadSnapshot(mailbox: mailbox, mailboxName: mailboxName, uidValidity: 1, unreadUIDs: Set(uids))
    }

    static func makeDefaults() -> UserDefaults {
        let suiteName = "mailbell.AccountSupervisorTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

final class SpyMonitor: AccountMonitoring {
    weak var delegate: MailMonitorDelegate?
    private(set) var account: MailAccount
    var hasSession: Bool
    private(set) var includeSpam: Bool
    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0
    private(set) var forceReconnectCallCount = 0
    private(set) var refreshNowCallCount = 0

    init(account: MailAccount, hasSession: Bool, includeSpam: Bool = false) {
        self.account = account
        self.hasSession = hasSession
        self.includeSpam = includeSpam
    }

    func updateAccount(_ account: MailAccount) {
        self.account = account
    }

    func hasStoredSession() throws -> Bool {
        hasSession
    }

    func start() {
        startCallCount += 1
    }

    func stop(clearSession _: Bool) {
        stopCallCount += 1
    }

    func forceReconnect() {
        forceReconnectCallCount += 1
    }

    func refreshNow() {
        refreshNowCallCount += 1
    }

    func setIncludeSpam(_ includeSpam: Bool) {
        self.includeSpam = includeSpam
    }
}
