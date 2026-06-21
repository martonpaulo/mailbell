import Foundation

protocol MailMonitorDelegate: AnyObject {
    func monitor(_ accountID: UUID, pendingUIDsFor mailbox: MessageMailbox) async -> Set<Int>
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

    func updateAccount(_ account: MailAccount)
    func start()
    func stop(clearSession: Bool)
    func forceReconnect()
    func refreshNow()
    func setIncludeSpam(_ includeSpam: Bool)
}

/// Runs one account's IMAP connection state machine:
/// token refresh, IMAP connect/select/IDLE, gap-fill on reconnect, and token revocation.
final class MailMonitor: AccountMonitoring, @unchecked Sendable {
    struct NotificationPlan: Equatable {
        let uidsToFetch: [Int]
        let uidsToNotify: [Int]
        let lastSeenUID: Int
    }

    weak var delegate: MailMonitorDelegate?

    static let maximumNotificationsPerFetch = 10
    static let maximumFreshHeadersPerFetch = 50
    static let maximumReconciliationHeadersPerMailbox = 100

    private(set) var account: MailAccount
    private var includeSpam: Bool
    private var checkpoints: [MessageMailbox: CheckpointStore]
    private let tokenProvider: AccountTokenProvider

    private var client: IMAPClient?
    private var runTask: Task<Void, Never>?

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
        runTask = Task { [weak self] in
            await self?.runLoop()
        }
    }

    func stop(clearSession: Bool = false) {
        runTask?.cancel()
        runTask = nil
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
        guard account.isEnabled, tokenProvider.hasSession else { return }
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

    private func runLoop() async {
        var backoff: TimeInterval = 1
        while !Task.isCancelled {
            do {
                notifyStatus(.connecting)
                let accessToken = try await validAccessToken()
                let email = account.email

                let client = IMAPClient()
                self.client = client
                try await client.connect()
                try await authenticate(client: client, email: email, accessToken: accessToken)
                let mailboxes = try await monitoredMailboxes(client: client)
                try await reconcileCheckpoints(client: client, mailboxes: mailboxes)
                try await reconcileUnreadState(client: client, mailboxes: mailboxes)
                try await selectInbox(client: client)

                backoff = 1
                notifyStatus(.connected)
                try await idleLoop(client: client, mailboxes: mailboxes)
            } catch let error as OAuthClient.OAuthError {
                switch error {
                case .refreshFailed, .noRefreshToken:
                    // The refresh token is gone; only the user can fix this.
                    Log.error("Token revoked: \(error.localizedDescription)")
                    notifyStatus(.reauthRequired, error: error.localizedDescription)
                    return
                case .refreshUnavailable:
                    if Task.isCancelled { break }
                    Log.error("Token refresh deferred: \(error.localizedDescription)")
                    notifyStatus(.reconnecting, error: error.localizedDescription)
                    client?.disconnect()
                    client = nil
                    try? await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
                    backoff = min(backoff * 2, 60)
                default:
                    notifyStatus(.reauthRequired, error: error.localizedDescription)
                    return
                }
            } catch let error as IMAPClient.IMAPError {
                if case .authFailed = error {
                    Log.error("IMAP authentication rejected: \(error.localizedDescription)")
                    notifyStatus(.reauthRequired, error: error.localizedDescription)
                    client?.disconnect()
                    client = nil
                    return
                }
                if Task.isCancelled { break }
                Log.error("Connection dropped: \(error.localizedDescription)")
                notifyStatus(.reconnecting, error: error.localizedDescription)
                client?.disconnect()
                client = nil
                try? await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
                backoff = min(backoff * 2, 60)
            } catch {
                if Task.isCancelled { break }
                let userVisibleError = Self.userVisibleReconnectError(for: error)
                if let userVisibleError {
                    Log.error("Connection dropped: \(userVisibleError)")
                } else {
                    Log.info("Connection closed; reconnecting.")
                }
                notifyStatus(.reconnecting, error: userVisibleError)
                client?.disconnect()
                client = nil
                try? await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
                backoff = min(backoff * 2, 60)
            }
        }
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

    private func fetchAndNotify(client: IMAPClient, mailboxes: [MonitoredMailbox]) async throws {
        var fetchedHeaders: [MessageHeader] = []
        var notificationIdentities = Set<IMAPMessageIdentity>()

        for mailbox in mailboxes {
            try await client.selectMailbox(mailbox.name)
            let lastSeenUID = lastSeenUID(for: mailbox.role)
            let from = max(lastSeenUID + 1, 1)
            let uids = try await client.searchUnreadUIDs(fromUID: from)
            let plan = Self.notificationPlan(uids: uids, lastSeenUID: lastSeenUID)
            let headers = try await client.fetchHeaders(uids: plan.uidsToFetch)
                .map { $0.assigningMailbox(mailbox.role, name: mailbox.name) }
                .sorted { $0.uid < $1.uid }

            let uidsToNotify = Set(plan.uidsToNotify)
            notificationIdentities.formUnion(
                headers.compactMap { uidsToNotify.contains($0.uid) ? $0.imapIdentity : nil }
            )
            fetchedHeaders.append(contentsOf: headers)
            setLastSeenUID(max(lastSeenUID, plan.lastSeenUID), for: mailbox.role)
        }

        guard !fetchedHeaders.isEmpty else { return }
        let admittedIdentities = await delegate?.monitor(account.id, shouldNotify: fetchedHeaders)
            ?? Set(fetchedHeaders.compactMap(\.imapIdentity))

        for header in fetchedHeaders {
            guard let identity = header.imapIdentity,
                  admittedIdentities.contains(identity),
                  notificationIdentities.contains(identity)
            else {
                continue
            }
            let result = await NotificationManager.shared.notify(header, account: account)
            delegate?.monitor(account.id, didNotify: header, result: result)
        }
    }

    private func syncUnreadStore(client: IMAPClient, mailboxes: [MonitoredMailbox]) async throws {
        var snapshots: [MailboxUnreadSnapshot] = []
        var fetchedHeaders: [MessageHeader] = []
        for mailbox in mailboxes {
            try await client.selectMailbox(mailbox.name)
            let searchedUIDs = try await client.searchUnreadUIDs()
            let unreadUIDs = Set(searchedUIDs.filter { $0 > 0 })
            snapshots.append(
                MailboxUnreadSnapshot(mailbox: mailbox.role, mailboxName: mailbox.name, unreadUIDs: unreadUIDs)
            )

            let pendingUIDs = await delegate?.monitor(account.id, pendingUIDsFor: mailbox.role) ?? []
            let unknownUIDs = Array(unreadUIDs.subtracting(pendingUIDs)).sorted()
            let uidsToFetch = Array(unknownUIDs.suffix(Self.maximumReconciliationHeadersPerMailbox))
            let mailboxHeaders = try await client.fetchHeaders(uids: uidsToFetch)
                .map { $0.assigningMailbox(mailbox.role, name: mailbox.name) }
            fetchedHeaders.append(contentsOf: mailboxHeaders)
        }
        await delegate?.monitor(account.id, didReconcileUnread: snapshots, fetchedHeaders: fetchedHeaders)
    }

    static func notificationPlan(
        uids: [Int],
        lastSeenUID: Int,
        notificationLimit: Int = maximumNotificationsPerFetch,
        fetchLimit: Int = maximumFreshHeadersPerFetch
    ) -> NotificationPlan {
        let fresh = Array(Set(uids.filter { $0 > lastSeenUID })).sorted()
        guard let newestUID = fresh.last else {
            return NotificationPlan(uidsToFetch: [], uidsToNotify: [], lastSeenUID: lastSeenUID)
        }
        let uidsToFetch = fetchLimit > 0 ? Array(fresh.suffix(fetchLimit)) : []
        let uidsToNotify = notificationLimit > 0 ? Array(uidsToFetch.suffix(notificationLimit)) : []
        return NotificationPlan(uidsToFetch: uidsToFetch, uidsToNotify: uidsToNotify, lastSeenUID: newestUID)
    }

    static func monitoredMailboxes(includeSpam: Bool, spamMailboxName: String?) -> [MonitoredMailbox] {
        var mailboxes = [MonitoredMailbox(role: .inbox, name: "INBOX")]
        guard includeSpam,
              let spamMailboxName = spamMailboxName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !spamMailboxName.isEmpty
        else {
            return mailboxes
        }
        mailboxes.append(MonitoredMailbox(role: .spam, name: spamMailboxName))
        return mailboxes
    }

    static func userVisibleReconnectError(for error: Error) -> String? {
        if let connectionError = error as? IMAPConnection.ConnectionError,
           case .closed = connectionError {
            return nil
        }
        return error.localizedDescription
    }

    // MARK: - Tokens

    private func validAccessToken() async throws -> String {
        try await tokenProvider.validAccessToken()
    }

    private func refreshAccessToken() async throws -> String {
        try await tokenProvider.refreshAccessToken()
    }

    private func authenticate(client: IMAPClient, email: String, accessToken: String) async throws {
        do {
            try await client.authenticate(email: email, accessToken: accessToken)
        } catch let error as IMAPClient.IMAPError {
            guard case .authFailed = error else { throw error }
            let refreshedAccessToken = try await refreshAccessToken()
            try await client.authenticate(email: email, accessToken: refreshedAccessToken)
        }
    }

    // MARK: - Checkpoint / gap fill

    private func lastSeenUID(for mailbox: MessageMailbox) -> Int {
        checkpoints[mailbox]?.lastSeenUID ?? 0
    }

    private func setLastSeenUID(_ value: Int, for mailbox: MessageMailbox) {
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

struct MonitoredMailbox: Equatable {
    let role: MessageMailbox
    let name: String
}

struct MailboxUnreadSnapshot: Equatable {
    let mailbox: MessageMailbox
    let mailboxName: String
    let unreadUIDs: Set<Int>
}
