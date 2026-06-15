import AppKit
import Foundation
import Network

@MainActor
protocol AccountSupervisorDelegate: AnyObject {
    func accountSupervisorDidUpdate(states: [AccountRuntimeState], aggregateStatus: MonitorStatus)
}

@MainActor
final class AccountSupervisor {
    weak var delegate: AccountSupervisorDelegate?

    private let configProvider: () throws -> OAuthConfig
    let accountStore: AccountStore
    let emailStore: EmailStore
    private let monitorFactory: (MailAccount, OAuthConfig, Bool) -> any AccountMonitoring
    let webmailOpen: @MainActor (URL, MailAccount?) async -> WebmailOpenOutcome
    var accounts: [MailAccount]
    private var includeSpam: Bool
    private var monitors: [UUID: any AccountMonitoring] = [:]
    var statuses: [UUID: MonitorStatus] = [:]
    private var connectionErrors: [UUID: String] = [:]
    private var notificationErrors: [UUID: String] = [:]
    var webmailOpenErrors: [UUID: String] = [:]
    private var isAuthenticating = false

    private let pathMonitor = NWPathMonitor()
    private let pathQueue = DispatchQueue(label: AppIdentity.dispatchQueueLabel("path"))
    private var lastPathSatisfied = true
    private let wakeObserver = NotificationObserverToken()
    private var reconnectAllTask: Task<Void, Never>?

    init(
        configProvider: @escaping () throws -> OAuthConfig = OAuthConfig.loadOrThrow,
        accountStore: AccountStore = AccountStore(),
        emailStore: EmailStore = EmailStore(),
        includeSpam: Bool = false,
        monitorFactory: @escaping (MailAccount, OAuthConfig, Bool) -> any AccountMonitoring = { account, config, includeSpam in
            MailMonitor(account: account, config: config, includeSpam: includeSpam)
        },
        webmailOpen: @escaping @MainActor (URL, MailAccount?) async -> WebmailOpenOutcome = { url, account in
            await WebmailOpener.open(url: url, account: account)
        }
    ) {
        self.configProvider = configProvider
        self.accountStore = accountStore
        self.emailStore = emailStore
        self.includeSpam = includeSpam
        self.monitorFactory = monitorFactory
        self.webmailOpen = webmailOpen
        accounts = accountStore.loadAccounts()
        setupNetworkMonitoring()
        setupSleepWakeObservers()
        startEnabledAccounts()
    }

    deinit {
        reconnectAllTask?.cancel()
        pathMonitor.cancel()
        wakeObserver.remove()
    }

    var oauthSetupMessage: String? {
        do {
            _ = try configProvider()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    var accountStates: [AccountRuntimeState] {
        accounts
            .map { account in
                AccountRuntimeState(
                    account: account,
                    status: statuses[account.id] ?? initialStatus(for: account),
                    lastError: connectionErrors[account.id] ?? notificationErrors[account.id],
                    webmailOpenError: webmailOpenErrors[account.id]
                )
            }
            .sorted { left, right in
                if left.status.sortPriority != right.status.sortPriority {
                    return left.status.sortPriority < right.status.sortPriority
                }
                return left.account.email.localizedCaseInsensitiveCompare(right.account.email) == .orderedAscending
            }
    }

    var emailStoreItems: [EmailStoreItem] {
        emailStore.items
    }

    var menuBarIconSystemImage: String {
        emailStore.hasItems ? "bell.fill" : "bell"
    }

    var aggregateStatus: MonitorStatus {
        let enabledStates = accountStates.filter(\.account.isEnabled)
        guard !enabledStates.isEmpty else { return .signedOut }

        if enabledStates.contains(where: { $0.status == .reauthRequired }) {
            return .reauthRequired
        }
        if enabledStates.contains(where: { $0.status == .error }) {
            return .error
        }
        if enabledStates.contains(where: { $0.status == .connecting || $0.status == .reconnecting }) {
            return .reconnecting
        }
        if enabledStates.contains(where: { $0.status == .connected }) {
            return .connected
        }
        return .signedOut
    }

    func addGmailAccount() async throws {
        let config = try configProvider()
        let result = try await signIn(config: config)
        let account = signedInAccount(email: result.email, providerID: .gmail)
        try saveSession(result.tokens, account: account)
        accounts = accountStore.upsert(account)
        statuses[account.id] = .signedOut
        connectionErrors[account.id] = nil
        start(account)
        publish()
    }

    func reauthenticate(accountID: UUID) async throws {
        guard accounts.contains(where: { $0.id == accountID }) else {
            throw SupervisorError.missingAccount
        }

        let config = try configProvider()
        let result = try await signIn(config: config)
        guard let account = accounts.first(where: { $0.id == accountID }) else {
            throw SupervisorError.missingAccount
        }
        guard account.email.caseInsensitiveCompare(result.email) == .orderedSame else {
            throw SupervisorError.accountMismatch(expected: account.email, actual: result.email)
        }
        try saveSession(result.tokens, account: account)
        accounts = accountStore.upsert(account)
        statuses[account.id] = .signedOut
        connectionErrors[account.id] = nil
        start(account)
        publish()
    }

    func setEnabled(_ isEnabled: Bool, accountID: UUID) {
        guard var account = accounts.first(where: { $0.id == accountID }) else { return }
        account.isEnabled = isEnabled
        accounts = accountStore.upsert(account)

        if isEnabled {
            start(account)
        } else {
            monitors[accountID]?.stop(clearSession: false)
            statuses[accountID] = .signedOut
            connectionErrors[accountID] = nil
            notificationErrors[accountID] = nil
            webmailOpenErrors[accountID] = nil
        }
        publish()
    }

    func setIncludeSpam(_ includeSpam: Bool) {
        guard self.includeSpam != includeSpam else { return }
        self.includeSpam = includeSpam
        for monitor in monitors.values {
            monitor.setIncludeSpam(includeSpam)
        }
        if !includeSpam, emailStore.removeSpamItems() {
            publish()
            return
        }
        publish()
    }

    func reconnect(accountID: UUID) {
        guard let account = accounts.first(where: { $0.id == accountID }) else { return }
        guard let monitor = ensureMonitor(for: account) else {
            publish()
            return
        }
        if monitor.hasSession {
            monitor.forceReconnect()
            monitor.start()
        } else {
            statuses[accountID] = .reauthRequired
        }
        publish()
    }

    func remove(accountID: UUID) {
        monitors[accountID]?.stop(clearSession: true)
        monitors[accountID] = nil
        statuses[accountID] = nil
        connectionErrors[accountID] = nil
        notificationErrors[accountID] = nil
        webmailOpenErrors[accountID] = nil
        CheckpointStore(accountID: accountID).reset()
        CheckpointStore(accountID: accountID, mailbox: "SPAM").reset()
        TokenStore(accountID: accountID).clear()
        emailStore.removeAccount(accountID: accountID)
        accounts = accountStore.remove(accountID: accountID)
        publish()
    }

    func forceReconnectAll() {
        let enabledAccountIDs = accounts.filter(\.isEnabled).map(\.id)
        reconnectAllTask?.cancel()
        reconnectAllTask = Task { @MainActor [weak self, enabledAccountIDs] in
            for (index, accountID) in enabledAccountIDs.enumerated() {
                let jitter = UInt64.random(in: 0 ... 300_000_000)
                let stagger = UInt64(index) * 300_000_000
                do {
                    try await Task.sleep(nanoseconds: jitter + stagger)
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                self?.reconnectIfSessionExists(accountID: accountID)
            }
        }
        publish()
    }

    private func signedInAccount(email: String, providerID: MailProviderID) -> MailAccount {
        if var existing = accounts.first(where: {
            $0.providerID == providerID && $0.email.caseInsensitiveCompare(email) == .orderedSame
        }) {
            existing.email = email
            existing.isEnabled = true
            return existing
        }

        return MailAccount(providerID: providerID, email: email)
    }

    private func saveSession(_ tokens: GoogleTokens, account: MailAccount) throws {
        do {
            try TokenStore(accountID: account.id, providerID: account.providerID).save(tokens: tokens)
        } catch {
            Log.error("Failed to save account session: \(error.localizedDescription)")
            throw SupervisorError.sessionSaveFailed
        }
    }

    private func signIn(config: OAuthConfig) async throws -> (tokens: GoogleTokens, email: String) {
        guard !isAuthenticating else { throw SupervisorError.authenticationInProgress }
        isAuthenticating = true
        defer { isAuthenticating = false }
        return try await OAuthClient(config: config).signIn()
    }

    private func startEnabledAccounts() {
        for account in accounts where account.isEnabled {
            start(account)
        }
        publish()
    }

    private func start(_ account: MailAccount) {
        guard let monitor = ensureMonitor(for: account) else { return }
        monitor.start()
    }

    private func reconnectIfSessionExists(accountID: UUID) {
        guard let account = accounts.first(where: { $0.id == accountID && $0.isEnabled }) else { return }
        guard let monitor = ensureMonitor(for: account) else { return }
        guard monitor.hasSession else { return }
        monitor.forceReconnect()
        monitor.start()
    }

    func ensureMonitor(for account: MailAccount) -> (any AccountMonitoring)? {
        if let monitor = monitors[account.id] {
            monitor.updateAccount(account)
            return monitor
        }

        do {
            let config = try configProvider()
            let monitor = monitorFactory(account, config, includeSpam)
            monitor.delegate = self
            monitors[account.id] = monitor
            statuses[account.id] = initialStatus(for: account)
            return monitor
        } catch {
            statuses[account.id] = .error
            connectionErrors[account.id] = error.localizedDescription
            return nil
        }
    }

    private func initialStatus(for account: MailAccount) -> MonitorStatus {
        guard account.isEnabled else { return .signedOut }
        return .signedOut
    }

    func publish() {
        delegate?.accountSupervisorDidUpdate(states: accountStates, aggregateStatus: aggregateStatus)
    }
}

private extension AccountSupervisor {
    func setupNetworkMonitoring() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            Task { @MainActor in
                self?.handlePathUpdate(satisfied: satisfied)
            }
        }
        pathMonitor.start(queue: pathQueue)
    }

    func handlePathUpdate(satisfied: Bool) {
        let recovered = satisfied && !lastPathSatisfied
        lastPathSatisfied = satisfied
        if recovered {
            Log.info("Network recovered; forcing account reconnects.")
            forceReconnectAll()
        }
    }

    func setupSleepWakeObservers() {
        let token = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                Log.info("System woke; forcing account reconnects.")
                self?.forceReconnectAll()
            }
        }
        wakeObserver.store(token)
    }
}

extension AccountSupervisor: MailMonitorDelegate {
    nonisolated func monitor(_ accountID: UUID, didSyncUnread headers: [MessageHeader]) async {
        await MainActor.run { [weak self] in
            guard let self,
                  let account = accounts.first(where: { $0.id == accountID })
            else {
                return
            }
            let filteredHeaders = includeSpam ? headers : headers.filter { $0.mailbox != .spam }
            if emailStore.replaceUnread(headers: filteredHeaders, account: account) {
                publish()
            }
        }
    }

    nonisolated func monitor(_ accountID: UUID, shouldNotify header: MessageHeader) async -> Bool {
        await MainActor.run { [weak self] in
            guard let self,
                  let account = accounts.first(where: { $0.id == accountID })
            else {
                return false
            }
            guard includeSpam || header.mailbox != .spam else {
                return false
            }
            let didAdmit = emailStore.admit(header: header, account: account)
            if didAdmit {
                publish()
            }
            return didAdmit
        }
    }

    nonisolated func monitor(_ accountID: UUID, didChangeStatus status: MonitorStatus, error: String?) {
        Task { @MainActor [weak self] in
            self?.statuses[accountID] = status
            if let error {
                self?.connectionErrors[accountID] = error
            } else if status.clearsLastError {
                self?.connectionErrors[accountID] = nil
            }
            self?.publish()
        }
    }

    nonisolated func monitor(_ accountID: UUID, didNotify _: MessageHeader, result: NotificationPostResult) {
        Task { @MainActor [weak self] in
            if let message = result.userMessage {
                self?.notificationErrors[accountID] = message
            } else {
                self?.notificationErrors[accountID] = nil
            }
            self?.publish()
        }
    }
}
