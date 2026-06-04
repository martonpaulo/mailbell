import AppKit
import Foundation
import Network

@MainActor
protocol AccountSupervisorDelegate: AnyObject {
    func accountSupervisorDidUpdate(states: [AccountRuntimeState], aggregateStatus: MonitorStatus)
}

@MainActor
final class AccountSupervisor {
    enum SupervisorError: LocalizedError {
        case needsConfig
        case missingAccount
        case authenticationInProgress
        case accountMismatch(expected: String, actual: String)

        var errorDescription: String? {
            switch self {
            case .needsConfig:
                return "Add a Google OAuth client before signing in."
            case .missingAccount:
                return "Account not found."
            case .authenticationInProgress:
                return "Google sign-in is already in progress."
            case let .accountMismatch(expected, actual):
                return "Signed in as \(actual), but this account expects \(expected)."
            }
        }
    }

    weak var delegate: AccountSupervisorDelegate?

    private var config: OAuthConfig?
    private let accountStore: AccountStore
    private var accounts: [MailAccount]
    private var monitors: [UUID: MailMonitor] = [:]
    private var statuses: [UUID: MonitorStatus] = [:]
    private var connectionErrors: [UUID: String] = [:]
    private var notificationErrors: [UUID: String] = [:]
    private var isAuthenticating = false

    private let pathMonitor = NWPathMonitor()
    private let pathQueue = DispatchQueue(label: "com.samzong.mailbell.path")
    private var lastPathSatisfied = true
    private var wakeObserver: NSObjectProtocol?

    init(config: OAuthConfig?, accountStore: AccountStore = AccountStore()) {
        self.config = config
        self.accountStore = accountStore
        accounts = accountStore.loadAccounts()
        setupNetworkMonitoring()
        setupSleepWakeObservers()
        startEnabledAccounts()
    }

    var accountStates: [AccountRuntimeState] {
        accounts
            .map { account in
                AccountRuntimeState(
                    account: account,
                    status: statuses[account.id] ?? initialStatus(for: account),
                    lastError: connectionErrors[account.id] ?? notificationErrors[account.id]
                )
            }
            .sorted { left, right in
                if left.status.sortPriority != right.status.sortPriority {
                    return left.status.sortPriority < right.status.sortPriority
                }
                return left.account.email.localizedCaseInsensitiveCompare(right.account.email) == .orderedAscending
            }
    }

    var aggregateStatus: MonitorStatus {
        guard config != nil else { return .needsConfig }
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

    func reconfigure(_ config: OAuthConfig?) {
        self.config = config
        for monitor in monitors.values {
            monitor.reconfigure(config)
        }
        if config != nil {
            startEnabledAccounts()
        }
        publish()
    }

    func addGmailAccount() async throws {
        guard let config else { throw SupervisorError.needsConfig }

        let result = try await signIn(config: config)
        let account = upsertSignedInAccount(email: result.email, providerID: .gmail)
        TokenStore(accountID: account.id, providerID: account.providerID).save(tokens: result.tokens)
        start(account)
        publish()
    }

    func reauthenticate(accountID: UUID) async throws {
        guard let config else { throw SupervisorError.needsConfig }
        guard accounts.contains(where: { $0.id == accountID }) else {
            throw SupervisorError.missingAccount
        }

        let result = try await signIn(config: config)
        guard let account = accounts.first(where: { $0.id == accountID }) else {
            throw SupervisorError.missingAccount
        }
        guard account.email.caseInsensitiveCompare(result.email) == .orderedSame else {
            throw SupervisorError.accountMismatch(expected: account.email, actual: result.email)
        }
        accounts = accountStore.upsert(account)
        TokenStore(accountID: account.id, providerID: account.providerID).save(tokens: result.tokens)
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
            monitors[accountID]?.stop()
            statuses[accountID] = .signedOut
            connectionErrors[accountID] = nil
            notificationErrors[accountID] = nil
        }
        publish()
    }

    func reconnect(accountID: UUID) {
        guard let account = accounts.first(where: { $0.id == accountID }) else { return }
        let monitor = ensureMonitor(for: account)
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
        CheckpointStore(accountID: accountID).reset()
        TokenStore(accountID: accountID).clear()
        accounts = accountStore.remove(accountID: accountID)
        publish()
    }

    func forceReconnectAll() {
        let enabledAccounts = accounts.filter(\.isEnabled)
        for (index, account) in enabledAccounts.enumerated() {
            let jitter = UInt64.random(in: 0 ... 300_000_000)
            let stagger = UInt64(index) * 300_000_000
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: jitter + stagger)
                self?.reconnectIfSessionExists(accountID: account.id)
            }
        }
        publish()
    }

    private func upsertSignedInAccount(email: String, providerID: MailProviderID) -> MailAccount {
        if var existing = accounts.first(where: {
            $0.providerID == providerID && $0.email.caseInsensitiveCompare(email) == .orderedSame
        }) {
            existing.email = email
            existing.isEnabled = true
            accounts = accountStore.upsert(existing)
            return existing
        }

        let account = MailAccount(providerID: providerID, email: email)
        accounts = accountStore.upsert(account)
        return account
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
        let monitor = ensureMonitor(for: account)
        if monitor.hasSession {
            monitor.start()
        } else {
            statuses[account.id] = .signedOut
        }
    }

    private func reconnectIfSessionExists(accountID: UUID) {
        guard let account = accounts.first(where: { $0.id == accountID && $0.isEnabled }) else { return }
        let monitor = ensureMonitor(for: account)
        guard monitor.hasSession else { return }
        monitor.forceReconnect()
        monitor.start()
    }

    private func ensureMonitor(for account: MailAccount) -> MailMonitor {
        if let monitor = monitors[account.id] {
            monitor.updateAccount(account)
            monitor.reconfigure(config)
            return monitor
        }

        let monitor = MailMonitor(account: account, config: config)
        monitor.delegate = self
        monitors[account.id] = monitor
        statuses[account.id] = initialStatus(for: account)
        return monitor
    }

    private func initialStatus(for account: MailAccount) -> MonitorStatus {
        guard config != nil else { return .needsConfig }
        guard account.isEnabled else { return .signedOut }
        return .signedOut
    }

    private func publish() {
        delegate?.accountSupervisorDidUpdate(states: accountStates, aggregateStatus: aggregateStatus)
    }

    private func setupNetworkMonitoring() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            Task { @MainActor in
                self?.handlePathUpdate(satisfied: satisfied)
            }
        }
        pathMonitor.start(queue: pathQueue)
    }

    private func handlePathUpdate(satisfied: Bool) {
        let recovered = satisfied && !lastPathSatisfied
        lastPathSatisfied = satisfied
        if recovered {
            Log.info("Network recovered; forcing account reconnects.")
            forceReconnectAll()
        }
    }

    private func setupSleepWakeObservers() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                Log.info("System woke; forcing account reconnects.")
                self?.forceReconnectAll()
            }
        }
    }
}

extension AccountSupervisor: MailMonitorDelegate {
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

private extension MonitorStatus {
    var clearsLastError: Bool {
        switch self {
        case .needsConfig, .signedOut, .connecting, .connected:
            return true
        case .reconnecting, .reauthRequired, .error:
            return false
        }
    }
}
