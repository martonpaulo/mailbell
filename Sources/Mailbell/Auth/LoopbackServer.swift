import Foundation
import Network

/// A one-shot loopback HTTP server used to capture the OAuth redirect for the
/// installed-app flow (redirect URI `http://127.0.0.1:<port>`).
final class LoopbackServer: @unchecked Sendable {
    enum LoopbackError: Error, LocalizedError, Equatable {
        case failedToStart
        case timedOut

        var errorDescription: String? {
            switch self {
            case .failedToStart:
                "Could not start the local OAuth callback server."
            case .timedOut:
                "Google sign-in timed out. Try again from Mailbell."
            }
        }
    }

    /// Ports Chrome allows for loopback and that are unlikely to be in use.
    /// Chrome blocks many well-known ports (ERR_UNSAFE_PORT); ephemeral OS picks
    /// can land on them. We bind an explicit safe port instead of `.any`.
    private static let preferredPorts: [UInt16] = [
        49200, 49201, 49202, 49203, 49204,
        8765, 8766, 8767,
        49188, 49189, 49190
    ]
    private static let callbackTimeout: TimeInterval = 5 * 60

    private var listener: NWListener?
    private let queue = DispatchQueue(label: AppIdentity.dispatchQueueLabel("loopback"))
    private var continuation: CheckedContinuation<[URLQueryItem], Error>?
    private var didResume = false
    private var pendingResult: Result<[URLQueryItem], Error>?

    private(set) var port: UInt16 = 0

    var redirectURI: String {
        guard port > 0 else {
            preconditionFailure("redirectURI requested before the listener is ready")
        }
        return "http://127.0.0.1:\(port)"
    }

    /// Starts listening on a loopback port. Must complete before building the
    /// authorization URL so the redirect URI is known.
    func start() async throws {
        var lastError: Error?
        for candidate in Self.preferredPorts {
            do {
                try await bind(to: candidate)
                Log.info("OAuth loopback listening on port \(port)")
                return
            } catch {
                lastError = error
            }
        }
        Log.error("OAuth loopback failed to bind: \(lastError?.localizedDescription ?? "unknown")")
        throw LoopbackError.failedToStart
    }

    private func bind(to candidate: UInt16) async throws {
        let params = NWParameters.tcp
        params.requiredInterfaceType = .loopback
        params.allowLocalEndpointReuse = true

        let listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: candidate)!)
        self.listener = listener

        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let resumeGate = OneShotResumeGate()
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    guard let assigned = listener.port?.rawValue, assigned > 0 else {
                        if resumeGate.claim() {
                            cont.resume(throwing: LoopbackError.failedToStart)
                        }
                        return
                    }
                    port = assigned
                    if resumeGate.claim() {
                        cont.resume()
                    }
                case let .failed(error):
                    listener.cancel()
                    if resumeGate.claim() {
                        cont.resume(throwing: error)
                    }
                case .cancelled:
                    if resumeGate.claim() {
                        cont.resume(throwing: LoopbackError.failedToStart)
                    }
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
    }

    /// Waits for the browser to hit the redirect URI and returns the query items.
    func waitForCallback(timeout: TimeInterval = LoopbackServer.callbackTimeout) async throws -> [URLQueryItem] {
        try await withCheckedThrowingContinuation { cont in
            queue.async {
                if let pending = self.pendingResult {
                    self.pendingResult = nil
                    cont.resume(with: pending)
                } else {
                    self.continuation = cont
                    self.scheduleCallbackTimeout(after: timeout)
                }
            }
        }
    }

    func stop() {
        listener?.stateUpdateHandler = nil
        listener?.cancel()
        listener = nil
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
            guard let self else { return }
            guard let data, let request = String(data: data, encoding: .utf8),
                  let line = request.split(separator: "\r\n").first
            else {
                respond(connection, succeeded: false)
                return
            }
            // Request line looks like: GET /?code=...&state=... HTTP/1.1
            let parts = line.split(separator: " ")
            guard parts.count >= 2 else {
                respond(connection, succeeded: false)
                return
            }
            let path = String(parts[1])
            var comps = URLComponents()
            comps.query = path.contains("?") ? String(path.split(separator: "?", maxSplits: 1)[1]) : ""
            let items = comps.queryItems ?? []
            respond(connection, succeeded: true)
            resume(.success(items))
        }
    }

    private func respond(_ connection: NWConnection, succeeded: Bool) {
        let title = succeeded ? "Mailbell connected" : "Mailbell error"
        let body = succeeded
            ? "You can close this tab and return to Mailbell."
            : "Authorization failed. Please try again from Mailbell."
        let html = """
        <!doctype html><html><head><meta charset="utf-8"><title>\(title)</title></head>
        <body style="font-family:-apple-system,sans-serif;text-align:center;padding-top:80px">
        <h2>\(title)</h2><p>\(body)</p></body></html>
        """
        let response = """
        HTTP/1.1 200 OK\r
        Content-Type: text/html; charset=utf-8\r
        Content-Length: \(html.utf8.count)\r
        Connection: close\r
        \r
        \(html)
        """
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func resume(_ result: Result<[URLQueryItem], Error>) {
        guard !didResume else { return }
        didResume = true
        if let cont = continuation {
            continuation = nil
            cont.resume(with: result)
        } else {
            pendingResult = result
        }
    }

    private func scheduleCallbackTimeout(after timeout: TimeInterval) {
        let clampedTimeout = max(timeout, 0)
        let nanoseconds = Int(clampedTimeout * 1_000_000_000)
        queue.asyncAfter(deadline: .now() + .nanoseconds(nanoseconds)) { [weak self] in
            self?.resume(.failure(LoopbackError.timedOut))
        }
    }
}
