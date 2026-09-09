import Foundation

protocol MailMonitorDelegate: AnyObject {
    func monitor(
        _ accountID: UUID,
        uidsToSkipFor mailbox: MessageMailbox,
        mailboxName: String,
        uidValidity: Int
    ) async -> Set<Int>
    func monitor(
        _ accountID: UUID,
        didReconcileUnread snapshots: [MailboxUnreadSnapshot],
        fetchedHeaders: [MessageHeader]
    ) async
    func monitor(_ accountID: UUID, shouldNotify headers: [MessageHeader]) async -> Set<IMAPMessageIdentity>
    func monitor(_ accountID: UUID, didChangeStatus status: MonitorStatus, error: String?)
    func monitor(_ accountID: UUID, didNotify header: MessageHeader, result: NotificationPostResult)
}

protocol AccountMonitoring: AnyObject {
    var delegate: MailMonitorDelegate? { get set }
    var account: MailAccount { get }
    var hasSession: Bool { get }

    func hasStoredSession() throws -> Bool
    func updateAccount(_ account: MailAccount)
    func start()
    func stop(clearSession: Bool)
    func forceReconnect()
    func refreshNow()
    func setIncludeSpam(_ includeSpam: Bool)
}

// swiftlint:disable type_body_length
/// Runs one account's IMAP connection state machine:
/// token refresh, IMAP connect/select/IDLE, gap-fill on reconnect, and token revocation.
final class MailMonitor: AccountMonitoring, @unchecked Sendable {
    struct NotificationPlan: Equatable {
        let admissionBatches: [[Int]]
        let uidsToNotify: [Int]
        let lastSeenUID: Int

        var uidsToAdmit: [Int] {
            admissionBatches.flatMap(\.self)
        }
    }

    weak var delegate: MailMonitorDelegate?

    static let maximumNotificationsPerFetch = 10
    static let maximumFreshHeadersPerAdmissionBatch = 100
    static let maximumReconciliationHeadersPerMailbox = 100

    private(set) var account: MailAccount
    private var includeSpam: Bool
    private var checkpoints: [MessageMailbox: CheckpointStore]
    let tokenProvider: AccountTokenProvider

    private var client: IMAPClient?
    private var runTask: Task<Void, Never>?
    /// Which run owns this account right now.
    ///
    /// A run suspends on the network in several places. Cancellation alone does
    /// not stop the resumed continuation from assigning a client or publishing
    /// status, so every effect is gated on the run still being the current one.
    private var runGeneration = 0

    /// Suspension seam. Production goes straight to the token provider; a test
    /// substitutes a call it can hold open at the exact point the old run has
    /// to be overtaken.
    var accessTokenSource: (@Sendable () async throws -> String)?

    /// IDLE re-arm window: below the 29-minute IMAP limit (RFC 2177).
    private let idleTimeout: TimeInterval = 25 * 60

    init(account: MailAccount, config: OAuthConfig, includeSpam: Bool = false) {
        self.account = account
        self.includeSpam = includeSpam
        checkpoints = Self.checkpoints(accountID: account.id)
        tokenProvider = AccountTokenProvider(accountID: account.id, providerID: account.providerID, config: config)
    }

    var hasSession: Bool {
        tokenProvider.hasSession
    }

    func hasStoredSession() throws -> Bool {
        try tokenProvider.hasStoredSession()
    }

    func updateAccount(_ account: MailAccount) {
        self.account = account
        checkpoints = Self.checkpoints(accountID: account.id)
    }

    // MARK: - Public actions

    func start() {
        guard account.isEnabled else { return }
        runTask?.cancel()
        client?.disconnect()
        client = nil
        runGeneration &+= 1
        let generation = runGeneration
        runTask = Task { [weak self] in
            await self?.runLoop(generation: generation)
        }
    }

    func stop(clearSession: Bool = false) {
        runTask?.cancel()
        runTask = nil
        // Retires the running generation, so anything it resumes into is inert.
        runGeneration &+= 1
        client?.disconnect()
        client = nil
        if clearSession {
            tokenProvider.clear()
            for checkpoint in checkpoints.values {
                checkpoint.reset()
            }
        }
        notifyStatus(.signedOut)
    }

    /// Forces the current connection to drop so the run loop reconnects promptly
    /// (used on network-available and wake).
    func forceReconnect() {
        client?.disconnect()
    }

    /// Requests an immediate gap-fill using the existing run loop. If a client is
    /// in IDLE, dropping it makes the retained run loop reconnect and fetch.
    func refreshNow() {
        guard account.isEnabled, (try? tokenProvider.hasStoredSession()) == true else { return }
        guard client != nil else {
            start()
            return
        }
        client?.disconnect()
    }

    func setIncludeSpam(_ includeSpam: Bool) {
        guard self.includeSpam != includeSpam else { return }
        self.includeSpam = includeSpam
        client?.disconnect()
    }

    // MARK: - Run loop (state machine)

    private func runLoop(generation: Int) async {
        var backoff: TimeInterval = 1
        while !Task.isCancelled, isCurrentRun(generation) {
            do {
                notifyStatus(.connecting, generation: generation)
                let accessToken = try await validAccessToken()
                // The first check that matters: token retrieval suspends, and a
                // stop or restart during it must not let this run take
                // ownership of the account again.
                guard isCurrentRun(generation) else { return }
                let email = account.email

                let client = IMAPClient()
                self.client = client
                try await client.connect()
                guard isCurrentRun(generation) else {
                    client.disconnect()
                    return
                }
                try await authenticate(client: client, email: email, accessToken: accessToken)
                let mailboxes = try await monitoredMailboxes(client: client)
                guard isCurrentRun(generation) else {
                    client.disconnect()
                    return
                }
                // Guarded before any durable effect: checkpoints move and
                // messages are admitted past this point.
                try await reconcileCheckpoints(client: client, mailboxes: mailboxes)
                try await reconcileUnreadState(client: client, mailboxes: mailboxes)
                try await selectInbox(client: client)
                guard isCurrentRun(generation) else {
                    client.disconnect()
                    return
                }

                backoff = 1
                notifyStatus(.connected, generation: generation)
                try await idleLoop(client: client, mailboxes: mailboxes)
            } catch {
                switch await handleRunFailure(error, backoff: &backoff) {
                case .retry:
                    continue
                case .stop:
                    return
                }
            }
        }
    }

    /// What a failed run should do next. Reconnect is the default; only a
    /// credential the user must replace, or a cancelled run, ends the loop.
    private enum RunOutcome {
        case retry
        case stop
    }

    private func handleRunFailure(_ error: Error, backoff: inout TimeInterval) async -> RunOutcome {
        if let oauthError = error as? OAuthClient.OAuthError {
            switch oauthError {
            case .refreshFailed, .noRefreshToken:
                // The refresh token is gone; only the user can fix this.
                Log.error("Token revoked: \(oauthError.localizedDescription)")
                notifyStatus(.reauthRequired, error: oauthError.localizedDescription)
                releaseClient()
                return .stop
            default:
                Log.error("Token refresh deferred: \(oauthError.localizedDescription)")
                return await backOff(&backoff, reportingError: oauthError.localizedDescription)
            }
        }

        if case .authFailed = error as? IMAPClient.IMAPError {
            Log.error("IMAP authentication rejected: \(error.localizedDescription)")
            notifyStatus(.reauthRequired, error: error.localizedDescription)
            releaseClient()
            return .stop
        }

        guard !Task.isCancelled else { return .stop }

        if error is IMAPClient.IMAPError {
            Log.error("Connection dropped: \(error.localizedDescription)")
            return await backOff(&backoff, reportingError: error.localizedDescription)
        }

        // A closed connection during shutdown is ordinary, so it is logged as
        // information and never surfaced as an error the user should act on.
        let userVisibleError = Self.userVisibleReconnectError(for: error)
        if let userVisibleError {
            Log.error("Connection dropped: \(userVisibleError)")
        } else {
            Log.info("Connection closed; reconnecting.")
        }
        return await backOff(&backoff, reportingError: userVisibleError)
    }

    private func backOff(_ backoff: inout TimeInterval, reportingError error: String?) async -> RunOutcome {
        notifyStatus(.reconnecting, error: error)
        releaseClient()
        try? await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
        backoff = min(backoff * 2, 60)
        return .retry
    }

    private func releaseClient() {
        client?.disconnect()
        client = nil
    }

    private func idleLoop(client: IMAPClient, mailboxes: [MonitoredMailbox]) async throws {
        while !Task.isCancelled {
            let event = try await client.idle(timeout: idleTimeout)
            try await handleIdleCycle(event: event, client: client, mailboxes: mailboxes)
            if event == .timedOut {
                continue // re-arm IDLE
            }
        }
    }

    func handleIdleCycle(
        event: IMAPClient.IdleEvent,
        client: IMAPClient,
        mailboxes: [MonitoredMailbox]
    ) async throws {
        switch event {
        case .timedOut, .newMessages, .mailboxChanged:
            try await reconcileUnreadState(client: client, mailboxes: mailboxes)
            try await selectInbox(client: client)
        }
    }

    func reconcileUnreadState(client: IMAPClient, mailboxes: [MonitoredMailbox]) async throws {
        try await fetchAndNotify(client: client, mailboxes: mailboxes)
        try await syncUnreadStore(client: client, mailboxes: mailboxes)
    }

    func lastSeenUID(for mailbox: MessageMailbox) -> Int {
        checkpoints[mailbox]?.lastSeenUID ?? 0
    }

    func setLastSeenUID(_ value: Int, for mailbox: MessageMailbox) {
        checkpoints[mailbox]?.lastSeenUID = value
    }

    private func storedUIDValidity(for mailbox: MessageMailbox) -> Int {
        checkpoints[mailbox]?.storedUIDValidity ?? 0
    }

    private func setStoredUIDValidity(_ value: Int, for mailbox: MessageMailbox) {
        checkpoints[mailbox]?.storedUIDValidity = value
    }

    /// Decides whether to gap-fill, rebaseline, or start clean using the
    /// `(UIDVALIDITY, lastSeenUID)` checkpoint.
    private func reconcileCheckpoints(client: IMAPClient, mailboxes: [MonitoredMailbox]) async throws {
        for mailbox in mailboxes {
            let state = try await client.selectMailbox(mailbox.name)
            try await reconcileCheckpoint(mailbox: state, role: mailbox.role)
        }
    }

    private func reconcileCheckpoint(mailbox: MailboxState, role: MessageMailbox) async throws {
        let baselineUID = max(mailbox.uidNext - 1, 0)
        if storedUIDValidity(for: role) == 0 {
            // First run: baseline to the current top so we do not notify the backlog.
            setStoredUIDValidity(mailbox.uidValidity, for: role)
            setLastSeenUID(baselineUID, for: role)
        } else if storedUIDValidity(for: role) != mailbox.uidValidity {
            // UIDVALIDITY changed: the old UIDs are meaningless. Rebaseline silently.
            Log.info("UIDVALIDITY changed; rebaselining without notifying backlog.")
            setStoredUIDValidity(mailbox.uidValidity, for: role)
            setLastSeenUID(baselineUID, for: role)
        }
        // Otherwise keep the checkpoint; idleLoop's initial fetch fills the gap.
    }

    // MARK: - Helpers

    private func notifyStatus(_ status: MonitorStatus, error: String? = nil) {
        delegate?.monitor(account.id, didChangeStatus: status, error: error)
    }

    /// A retired run must not publish status; its view of the account is stale.
    private func notifyStatus(_ status: MonitorStatus, error: String? = nil, generation: Int) {
        guard isCurrentRun(generation) else { return }
        notifyStatus(status, error: error)
    }

    func isCurrentRun(_ generation: Int) -> Bool {
        runGeneration == generation
    }

    var currentRunGeneration: Int {
        runGeneration
    }

    private func monitoredMailboxes(client: IMAPClient) async throws -> [MonitoredMailbox] {
        guard includeSpam else {
            return Self.monitoredMailboxes(includeSpam: false, spamMailboxName: nil)
        }
        do {
            let spamMailbox = try await client.mailboxName(for: .junk)
            if spamMailbox == nil {
                Log.error("Gmail Spam mailbox not found; continuing with Inbox only.")
            }
            return Self.monitoredMailboxes(includeSpam: true, spamMailboxName: spamMailbox)
        } catch {
            Log.error(
                "Could not discover Gmail Spam mailbox; continuing with Inbox only: \(error.localizedDescription)"
            )
            return Self.monitoredMailboxes(includeSpam: true, spamMailboxName: nil)
        }
    }

    private func selectInbox(client: IMAPClient) async throws {
        try await client.selectInbox()
    }

    private static func checkpoints(accountID: UUID) -> [MessageMailbox: CheckpointStore] {
        [
            .inbox: CheckpointStore(accountID: accountID, mailbox: "INBOX"),
            .spam: CheckpointStore(accountID: accountID, mailbox: "SPAM")
        ]
    }
}

// swiftlint:enable type_body_length

struct MonitoredMailbox: Equatable {
    let role: MessageMailbox
    let name: String
}

struct MailboxUnreadSnapshot: Equatable {
    let mailbox: MessageMailbox
    let mailboxName: String
    /// The generation the snapshot was taken under. Pending items captured
    /// under a different one are meaningless, not merely absent.
    let uidValidity: Int
    let unreadUIDs: Set<Int>
}
