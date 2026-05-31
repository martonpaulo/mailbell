import AppKit
import Foundation
import Network

protocol MailMonitorDelegate: AnyObject {
    func monitor(didChangeStatus status: AppState.Status, error: String?)
    func monitor(didUpdateAccount email: String?)
    func monitor(didNotify header: MessageHeader, result: NotificationPostResult)
}

/// Orchestrates the connection state machine described in docs/design.md:
/// sign-in, token refresh, IMAP connect/select/IDLE, gap-fill on reconnect, and
/// recovery from network changes, sleep/wake, and token revocation.
final class MailMonitor {
    weak var delegate: MailMonitorDelegate?

    private var config: OAuthConfig?
    private let store = TokenStore()
    private var oauth: OAuthClient?

    private var client: IMAPClient?
    private var runTask: Task<Void, Never>?
    private var signInTask: Task<Void, Never>?

    private let pathMonitor = NWPathMonitor()
    private let pathQueue = DispatchQueue(label: "com.samzong.mailbell.path")
    private var lastPathSatisfied = true

    /// IDLE re-arm window: below the 29-minute IMAP limit (RFC 2177).
    private let idleTimeout: TimeInterval = 25 * 60

    private let uidValidityKey = "mailbell.uidValidity"
    private let lastUIDKey = "mailbell.lastSeenUID"

    init(config: OAuthConfig?) {
        self.config = config
        oauth = config.map(OAuthClient.init)
        setupNetworkMonitoring()
        setupSleepWakeObservers()
    }

    var hasSession: Bool { store.hasSession }
    var accountEmail: String? { store.email }
    var isConfigured: Bool { config != nil }

    /// Applies a new OAuth client configuration (entered in Settings).
    func reconfigure(_ config: OAuthConfig?) {
        self.config = config
        oauth = config.map(OAuthClient.init)
    }

    // MARK: - Public actions

    func signIn() {
        guard let oauth else { return }
        signInTask?.cancel()
        notifyStatus(.connecting)
        signInTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await oauth.signIn()
                self.store.save(tokens: result.tokens, email: result.email)
                self.delegate?.monitor(didUpdateAccount: result.email)
                self.resetCheckpoint()
                self.start()
            } catch {
                Log.error("Sign-in failed: \(error.localizedDescription)")
                self.notifyStatus(.signedOut, error: error.localizedDescription)
            }
        }
    }

    func start() {
        guard config != nil, store.hasSession else { return }
        runTask?.cancel()
        runTask = Task { [weak self] in
            await self?.runLoop()
        }
    }

    func disconnect() {
        runTask?.cancel()
        runTask = nil
        client?.disconnect()
        client = nil
        store.clear()
        resetCheckpoint()
        notifyStatus(.signedOut)
        delegate?.monitor(didUpdateAccount: nil)
    }

    /// Forces the current connection to drop so the run loop reconnects promptly
    /// (used on network-available and wake).
    private func forceReconnect() {
        client?.disconnect()
    }

    // MARK: - Run loop (state machine)

    private func runLoop() async {
        var backoff: TimeInterval = 1
        while !Task.isCancelled {
            do {
                notifyStatus(.connecting)
                let accessToken = try await validAccessToken()
                guard let email = store.email else {
                    notifyStatus(.reauthRequired, error: "Missing account email")
                    return
                }

                let client = IMAPClient()
                self.client = client
                try await client.connect()
                try await client.authenticate(email: email, accessToken: accessToken)
                let mailbox = try await client.selectInbox()
                try await reconcileCheckpoint(mailbox: mailbox, client: client, email: email)

                backoff = 1
                notifyStatus(.connected)
                try await idleLoop(client: client, email: email)
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

    private func idleLoop(client: IMAPClient, email: String) async throws {
        // Catch up on anything that arrived before this connection settled.
        try await fetchAndNotify(client: client, email: email)

        while !Task.isCancelled {
            let event = try await client.idle(timeout: idleTimeout)
            switch event {
            case .timedOut:
                continue // re-arm IDLE
            case .newMessages:
                try await fetchAndNotify(client: client, email: email)
            }
        }
    }

    private func fetchAndNotify(client: IMAPClient, email: String) async throws {
        let from = lastSeenUID + 1
        let headers = try await client.fetchHeaders(fromUID: from)
        let fresh = headers.filter { $0.uid > lastSeenUID }.sorted { $0.uid < $1.uid }
        for header in fresh {
            let result = await NotificationManager.shared.notify(header, account: email)
            delegate?.monitor(didNotify: header, result: result)
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
        store.save(tokens: refreshed, email: store.email ?? "")
        return refreshed.accessToken
    }

    // MARK: - Checkpoint / gap fill

    private var lastSeenUID: Int {
        get { UserDefaults.standard.integer(forKey: lastUIDKey) }
        set { UserDefaults.standard.set(newValue, forKey: lastUIDKey) }
    }

    private var storedUIDValidity: Int {
        get { UserDefaults.standard.integer(forKey: uidValidityKey) }
        set { UserDefaults.standard.set(newValue, forKey: uidValidityKey) }
    }

    private func resetCheckpoint() {
        UserDefaults.standard.removeObject(forKey: uidValidityKey)
        UserDefaults.standard.removeObject(forKey: lastUIDKey)
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

    // MARK: - Network / sleep-wake

    private func setupNetworkMonitoring() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let satisfied = path.status == .satisfied
            let recovered = satisfied && !self.lastPathSatisfied
            self.lastPathSatisfied = satisfied
            if recovered {
                Log.info("Network recovered; forcing reconnect.")
                self.forceReconnect()
            }
        }
        pathMonitor.start(queue: pathQueue)
    }

    private func setupSleepWakeObservers() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Log.info("System woke; forcing reconnect.")
            self?.forceReconnect()
        }
    }

    // MARK: - Helpers

    private func notifyStatus(_ status: AppState.Status, error: String? = nil) {
        delegate?.monitor(didChangeStatus: status, error: error)
    }
}
