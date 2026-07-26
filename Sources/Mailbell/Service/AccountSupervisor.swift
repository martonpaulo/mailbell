import AppKit
import Foundation
import Network

@MainActor
protocol AccountSupervisorDelegate: AnyObject {
    func accountSupervisorDidUpdate(states: [AccountRuntimeState], aggregateStatus: MonitorStatus)
}

typealias AccountMonitorFactory = (MailAccount, OAuthConfig, Bool) -> any AccountMonitoring
typealias EmailReadMarker = (MailAccount, OAuthConfig, [IMAPMessageIdentity]) async throws -> Void

@MainActor
final class AccountSupervisor {
    weak var delegate: AccountSupervisorDelegate?

    let configProvider: () throws -> OAuthConfig
    let accountStore: AccountStore
    let emailStore: EmailStore
    private let monitorFactory: AccountMonitorFactory
    let emailReadMarker: EmailReadMarker
    let webmailOpen: @MainActor (URL, MailAccount?) async -> WebmailOpenOutcome
    let signInNeededNotifier: SignInNeededNotifier
    var accounts: [MailAccount]
    private var includeSpam: Bool
    private var monitors: [UUID: any AccountMonitoring] = [:]
    var statuses: [UUID: MonitorStatus] = [:] {
        didSet { notifyAccountsNeedingSignIn(previous: oldValue) }
    }
    var connectionErrors: [UUID: String] = [:]
    private var notificationErrors: [UUID: String] = [:]
    var webmailOpenErrors: [UUID: String] = [:]
    var accountStoreError: String?
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
        monitorFactory: @escaping AccountMonitorFactory = { account, config, includeSpam in
            MailMonitor(account: account, config: config, includeSpam: includeSpam)
        },
        emailReadMarker: @escaping EmailReadMarker = IMAPMessageReadMarker.markAsRead,
        webmailOpen: @escaping @MainActor (URL, MailAccount?) async -> WebmailOpenOutcome = { url, account in
            await WebmailOpener.open(url: url, account: account)
        },
        signInNeededNotifier: @escaping SignInNeededNotifier = { account in
            Task { await NotificationManager.shared.notifySignInNeeded(account: account) }
        }
    ) {
        self.configProvider = configProvider
        self.accountStore = accountStore
        self.emailStore = emailStore
        self.includeSpam = includeSpam
        self.monitorFactory = monitorFactory
        self.emailReadMarker = emailReadMarker
        self.webmailOpen = webmailOpen
        self.signInNeededNotifier = signInNeededNotifier
        do {
            accounts = try accountStore.loadAccounts()
        } catch {
            accounts = []
            accountStoreError = error.localizedDescription
            Log.error("Failed to load accounts: \(error.localizedDescription)")
        }
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

    /// True while any enabled account cannot monitor Gmail without the user
    /// acting (sign-in expired, or a surfaced connection failure).
    var needsAttention: Bool {
        accountStates.contains { $0.account.isEnabled && $0.status.needsAttention }
    }

    var menuBarIconSystemImage: String {
        MenuBarIcon.systemImage(needsAttention: needsAttention, hasPendingItems: emailStore.hasItems)
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
        accounts = try accountStore.upsert(account)
        accountStoreError = nil
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
        accounts = try accountStore.upsert(account)
        accountStoreError = nil
        statuses[account.id] = .signedOut
        connectionErrors[account.id] = nil
        start(account)
        publish()
    }

    func setEnabled(_ isEnabled: Bool, accountID: UUID) {
        guard var account = accounts.first(where: { $0.id == accountID }) else { return }
        account.isEnabled = isEnabled
        do {
            accounts = try accountStore.upsert(account)
            accountStoreError = nil
            connectionErrors[accountID] = nil
        } catch {
            accountStoreError = error.localizedDescription
            connectionErrors[accountID] = error.localizedDescription
            publish()
            return
        }

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
        guard let hasSession = hasStoredSession(monitor, accountID: accountID) else {
            publish()
            return
        }
        if hasSession {
            monitor.forceReconnect()
            monitor.start()
        } else {
            statuses[accountID] = .reauthRequired
        }
        publish()
    }

    func remove(accountID: UUID) {
        guard accounts.contains(where: { $0.id == accountID }) else { return }
        let remainingAccounts: [MailAccount]
        do {
            try emailStore.removeAccountRecords(accountID: accountID)
            remainingAccounts = try accountStore.remove(accountID: accountID)
            accountStoreError = nil
        } catch {
            accountStoreError = error.localizedDescription
            connectionErrors[accountID] = error.localizedDescription
            publish()
            return
        }

        monitors[accountID]?.stop(clearSession: true)
        monitors[accountID] = nil
        statuses[accountID] = nil
        connectionErrors[accountID] = nil
        notificationErrors[accountID] = nil
        webmailOpenErrors[accountID] = nil
        CheckpointStore(accountID: accountID).reset()
        CheckpointStore(accountID: accountID, mailbox: "SPAM").reset()
        TokenStore(accountID: accountID).clear()
        emailStore.removeAccountItems(accountID: accountID)
        accounts = remainingAccounts
        applyEmailStoreWarning(accountID: nil)
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
        guard hasStoredSession(monitor, accountID: accountID) == true else { return }
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

    func hasStoredSession(_ monitor: any AccountMonitoring, accountID: UUID) -> Bool? {
        do {
            return try monitor.hasStoredSession()
        } catch {
            statuses[accountID] = .error
            connectionErrors[accountID] = error.localizedDescription
            return nil
        }
    }

    func handleEmailStorePersistenceFailure(_ error: Error, accountID: UUID?) {
        applyEmailStorePersistenceFailure(error, accountID: accountID)
        publish()
    }

    /// Records a persistence failure without publishing, so bulk callers can
    /// batch a single update after every account has been processed.
    func applyEmailStorePersistenceFailure(_ error: Error, accountID: UUID?) {
        let message = error.localizedDescription
        Log.error("Email store persistence failed: \(message)")
        if let accountID {
            statuses[accountID] = .error
            connectionErrors[accountID] = message
        } else {
            accountStoreError = message
        }
    }

    @discardableResult
    func applyEmailStoreWarning(accountID: UUID?) -> Bool {
        guard let warning = emailStore.takePersistenceWarning() else { return false }
        Log.error(warning)
        if let accountID {
            connectionErrors[accountID] = warning
        } else {
            accountStoreError = warning
        }
        return true
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
    nonisolated func monitor(_ accountID: UUID, pendingUIDsFor mailbox: MessageMailbox) async -> Set<Int> {
        await MainActor.run { [weak self] in
            guard let self,
                  let account = accounts.first(where: { $0.id == accountID })
            else {
                return []
            }
            return emailStore.pendingUIDs(accountID: account.id, mailbox: mailbox)
        }
    }

    nonisolated func monitor(
        _ accountID: UUID,
        didReconcileUnread snapshots: [MailboxUnreadSnapshot],
        fetchedHeaders: [MessageHeader]
    ) async {
        await MainActor.run { [weak self] in
            guard let self,
                  let account = accounts.first(where: { $0.id == accountID })
            else {
                return
            }
            let visibleSnapshots = includeSpam ? snapshots : snapshots.filter { $0.mailbox != .spam }
            let visibleHeaders = includeSpam ? fetchedHeaders : fetchedHeaders.filter { $0.mailbox != .spam }
            do {
                let didChange = try emailStore.reconcileUnread(
                    snapshots: visibleSnapshots,
                    fetchedHeaders: visibleHeaders,
                    account: account
                )
                let didWarn = applyEmailStoreWarning(accountID: account.id)
                guard didChange || didWarn else { return }
                publish()
            } catch {
                handleEmailStorePersistenceFailure(error, accountID: account.id)
            }
        }
    }

    nonisolated func monitor(_ accountID: UUID, shouldNotify headers: [MessageHeader]) async -> Set<IMAPMessageIdentity> {
        await MainActor.run { [weak self] in
            guard let self,
                  let account = accounts.first(where: { $0.id == accountID })
            else {
                return []
            }
            let visibleHeaders = includeSpam ? headers : headers.filter { $0.mailbox != .spam }
            var admittedIdentities = Set<IMAPMessageIdentity>()
            var didChange = false

            for header in visibleHeaders {
                do {
                    guard try emailStore.admit(header: header, account: account) else { continue }
                    didChange = true
                    if let identity = header.imapIdentity {
                        admittedIdentities.insert(identity)
                    }
                } catch {
                    handleEmailStorePersistenceFailure(error, accountID: account.id)
                    return []
                }
            }

            let didWarn = applyEmailStoreWarning(accountID: account.id)
            if didChange || didWarn {
                publish()
            }
            return admittedIdentities
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
