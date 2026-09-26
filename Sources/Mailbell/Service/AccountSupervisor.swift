import AppKit
import Foundation
import MailbellKit
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
    let reviewQueue: ReviewQueue
    private let monitorFactory: AccountMonitorFactory
    let emailReadMarker: EmailReadMarker
    let webmailOpen: @MainActor (URL, MailAccount?) async -> WebmailOpenOutcome
    let signInNeededNotifier: SignInNeededNotifier
    var accounts: [MailAccount]
    var includeSpam: Bool
    var monitors: [UUID: any AccountMonitoring] = [:]
    var statuses: [UUID: MonitorStatus] = [:] {
        didSet { notifyAccountsNeedingSignIn(previous: oldValue) }
    }
    var connectionErrors: [UUID: String] = [:]
    var notificationErrors: [UUID: String] = [:]
    var webmailOpenErrors: [UUID: String] = [:]
    var accountStoreError: String?
    private var isAuthenticating = false

    let pathMonitor = NWPathMonitor()
    let pathQueue = DispatchQueue(label: AppIdentity.dispatchQueueLabel("path"))
    var lastPathSatisfied = true
    let wakeObserver = NotificationObserverToken()
    var reconnectAllTask: Task<Void, Never>?

    init(
        notifier: any MailNotifying,
        configProvider: @escaping () throws -> OAuthConfig = OAuthConfig.loadOrThrow,
        accountStore: AccountStore = AccountStore(),
        reviewQueue: ReviewQueue = ReviewQueue(),
        includeSpam: Bool = false,
        monitorFactory: AccountMonitorFactory? = nil,
        emailReadMarker: @escaping EmailReadMarker = IMAPMessageReadMarker.markAsRead,
        webmailOpen: @escaping @MainActor (URL, MailAccount?) async -> WebmailOpenOutcome = { url, account in
            await WebmailOpener.open(url: url, account: account)
        },
        signInNeededNotifier: SignInNeededNotifier? = nil
    ) {
        self.configProvider = configProvider
        self.accountStore = accountStore
        self.reviewQueue = reviewQueue
        self.includeSpam = includeSpam
        self.monitorFactory = monitorFactory ?? { account, config, includeSpam in
            MailMonitor(account: account, config: config, includeSpam: includeSpam, notifier: notifier)
        }
        self.emailReadMarker = emailReadMarker
        self.webmailOpen = webmailOpen
        self.signInNeededNotifier = signInNeededNotifier ?? { account in
            Task { await notifier.notifySignInNeeded(account: account) }
        }
        do {
            accounts = try accountStore.loadAccounts()
        } catch {
            accounts = []
            accountStoreError = error.localizedDescription
            Log.monitor.error("Failed to load accounts: \(Log.detail(error), privacy: .private)")
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

    var buildProblemDetails: String? {
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

    var shownItems: [ReviewItem] {
        reviewQueue.shownItems
    }

    /// True while any enabled account cannot monitor Gmail without the user
    /// acting (sign-in expired, or a surfaced connection failure).
    var needsAttention: Bool {
        accountStates.contains { $0.account.isEnabled && $0.status.needsAttention }
    }

    var needsSignIn: Bool {
        accountStates.contains { $0.account.isEnabled && $0.status.needsSignIn }
    }

    var menuBarIconSystemImage: String {
        MenuBarIcon.systemImage(needsAttention: needsAttention, hasPendingItems: reviewQueue.hasItems)
    }

    var aggregateStatus: MonitorStatus {
        let enabledStates = accountStates.filter(\.account.isEnabled)
        guard !enabledStates.isEmpty else { return .signedOut }

        if enabledStates.contains(where: { $0.status == .signInRequired }) {
            return .signInRequired
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

    func signedInAccount(email: String, providerID: MailProviderID) -> MailAccount {
        if var existing = accounts.first(where: {
            $0.providerID == providerID && $0.email.caseInsensitiveCompare(email) == .orderedSame
        }) {
            existing.email = email
            existing.isEnabled = true
            return existing
        }

        return MailAccount(providerID: providerID, email: email)
    }

    func saveSession(_ tokens: GoogleTokens, account: MailAccount) throws {
        do {
            try TokenStore(accountID: account.id, providerID: account.providerID).save(tokens: tokens)
        } catch {
            Log.monitor.error("Failed to save account session: \(Log.detail(error), privacy: .private)")
            throw SupervisorError.sessionSaveFailed
        }
    }

    func signIn(config: OAuthConfig) async throws -> (tokens: GoogleTokens, email: String) {
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

    func start(_ account: MailAccount) {
        guard let monitor = ensureMonitor(for: account) else { return }
        monitor.start()
    }

    func reconnectIfSessionExists(accountID: UUID) {
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

    func handleHandledHistoryFailure(_ error: Error, accountID: UUID?) {
        applyHandledHistoryFailure(error, accountID: accountID)
        publish()
    }

    /// Records a persistence failure without publishing, so bulk callers can
    /// batch a single update after every account has been processed.
    func applyHandledHistoryFailure(_ error: Error, accountID: UUID?) {
        let message = error.localizedDescription
        Log.monitor.error("Handled history persistence failed: \(Log.detail(error), privacy: .private)")
        if let accountID {
            statuses[accountID] = .error
            connectionErrors[accountID] = message
        } else {
            accountStoreError = message
        }
    }

    @discardableResult
    func applyReviewQueueWarning(accountID: UUID?) -> Bool {
        guard let warning = reviewQueue.takePersistenceWarning() else { return false }
        Log.monitor.error("Review queue warning: \(warning, privacy: .public)")
        if let accountID {
            connectionErrors[accountID] = warning
        } else {
            accountStoreError = warning
        }
        return true
    }
}

private extension AccountSupervisor {
}

extension AccountSupervisor: MailMonitorDelegate {
}
