import Foundation

protocol MailMonitorDelegate: AnyObject {
    func monitor(_ accountID: UUID, didChangeStatus status: MonitorStatus, error: String?)
    func monitor(_ accountID: UUID, didNotify header: MessageHeader, result: NotificationPostResult)
}

/// Runs one account's IMAP connection state machine:
/// token refresh, IMAP connect/select/IDLE, gap-fill on reconnect, and token revocation.
final class MailMonitor {
    weak var delegate: MailMonitorDelegate?

    private(set) var account: MailAccount
    private var config: OAuthConfig?
    private let store: TokenStore
    private var checkpoint: CheckpointStore
    private var oauth: OAuthClient?

    private var client: IMAPClient?
    private var runTask: Task<Void, Never>?

    /// IDLE re-arm window: below the 29-minute IMAP limit (RFC 2177).
    private let idleTimeout: TimeInterval = 25 * 60

    init(account: MailAccount, config: OAuthConfig?) {
        self.account = account
        self.config = config
        store = TokenStore(accountID: account.id, providerID: account.providerID)
        checkpoint = CheckpointStore(accountID: account.id)
        oauth = config.map(OAuthClient.init)
    }

    var hasSession: Bool { store.hasSession }
    var isConfigured: Bool { config != nil }

    func updateAccount(_ account: MailAccount) {
        self.account = account
        checkpoint = CheckpointStore(accountID: account.id)
    }

    /// Applies a new OAuth client configuration (entered in Settings).
    func reconfigure(_ config: OAuthConfig?) {
        self.config = config
        oauth = config.map(OAuthClient.init)
    }

    // MARK: - Public actions

    func start() {
        guard config != nil, account.isEnabled, store.hasSession else { return }
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
            store.clear()
            checkpoint.reset()
        }
        notifyStatus(.signedOut)
    }

    /// Forces the current connection to drop so the run loop reconnects promptly
    /// (used on network-available and wake).
    func forceReconnect() {
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
                try await client.authenticate(email: email, accessToken: accessToken)
                let mailbox = try await client.selectInbox()
                try await reconcileCheckpoint(mailbox: mailbox, client: client, email: email)

                backoff = 1
                notifyStatus(.connected)
                try await idleLoop(client: client)
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
            } catch {
                if Task.isCancelled { break }
                Log.error("Connection dropped: \(error.localizedDescription)")
                notifyStatus(.reconnecting, error: error.localizedDescription)
                client?.disconnect()
                client = nil
                try? await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
                backoff = min(backoff * 2, 60)
            }
        }
    }

    private func idleLoop(client: IMAPClient) async throws {
        // Catch up on anything that arrived before this connection settled.
        try await fetchAndNotify(client: client)

        while !Task.isCancelled {
            let event = try await client.idle(timeout: idleTimeout)
            switch event {
            case .timedOut:
                continue // re-arm IDLE
            case .newMessages:
                try await fetchAndNotify(client: client)
            }
        }
    }

    private func fetchAndNotify(client: IMAPClient) async throws {
        let from = lastSeenUID + 1
        let headers = try await client.fetchHeaders(fromUID: from)
        let fresh = headers.filter { $0.uid > lastSeenUID }.sorted { $0.uid < $1.uid }
        for header in fresh {
            let result = await NotificationManager.shared.notify(header, account: account)
            delegate?.monitor(account.id, didNotify: header, result: result)
            lastSeenUID = max(lastSeenUID, header.uid)
        }
    }

    // MARK: - Tokens

    private func validAccessToken() async throws -> String {
        guard let oauth else { throw OAuthClient.OAuthError.noRefreshToken }
        guard let tokens = store.loadTokens(), let refresh = tokens.refreshToken else {
            throw OAuthClient.OAuthError.noRefreshToken
        }
        if tokens.isAccessTokenValid, !tokens.accessToken.isEmpty {
            return tokens.accessToken
        }
        let refreshed = try await oauth.refresh(refreshToken: refresh)
        store.save(tokens: refreshed)
        return refreshed.accessToken
    }

    // MARK: - Checkpoint / gap fill

    private var lastSeenUID: Int {
        get { checkpoint.lastSeenUID }
        set { checkpoint.lastSeenUID = newValue }
    }

    private var storedUIDValidity: Int {
        get { checkpoint.storedUIDValidity }
        set { checkpoint.storedUIDValidity = newValue }
    }

    /// Decides whether to gap-fill, rebaseline, or start clean using the
    /// `(UIDVALIDITY, lastSeenUID)` checkpoint.
    private func reconcileCheckpoint(mailbox: MailboxState, client _: IMAPClient, email _: String) async throws {
        let baselineUID = max(mailbox.uidNext - 1, 0)
        if storedUIDValidity == 0 {
            // First run: baseline to the current top so we do not notify the backlog.
            storedUIDValidity = mailbox.uidValidity
            lastSeenUID = baselineUID
        } else if storedUIDValidity != mailbox.uidValidity {
            // UIDVALIDITY changed: the old UIDs are meaningless. Rebaseline silently.
            Log.info("UIDVALIDITY changed; rebaselining without notifying backlog.")
            storedUIDValidity = mailbox.uidValidity
            lastSeenUID = baselineUID
        }
        // Otherwise keep the checkpoint; idleLoop's initial fetch fills the gap.
    }

    // MARK: - Helpers

    private func notifyStatus(_ status: MonitorStatus, error: String? = nil) {
        delegate?.monitor(account.id, didChangeStatus: status, error: error)
    }
}
