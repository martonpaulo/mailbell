import FlyingFox
import FlyingSocks
import Foundation

/// A one-shot loopback HTTP server used to capture the OAuth redirect for the
/// installed-app flow (redirect URI `http://127.0.0.1:<port>/oauth/callback`).
actor LoopbackServer {
    struct Callback: Equatable {
        let code: String
    }

    enum LoopbackError: Error, LocalizedError, Equatable {
        case failedToStart
        case timedOut
        case cancelled
        case missingState
        case stateMismatch
        case missingCode
        case providerError(String)

        var errorDescription: String? {
            switch self {
            case .failedToStart:
                "Could not start the local OAuth callback server."
            case .timedOut:
                "Google sign-in timed out. Try again from Mailbell."
            case .cancelled:
                "Google sign-in was cancelled."
            case .missingState, .stateMismatch:
                "OAuth callback state did not match. Try signing in again."
            case .missingCode:
                "No authorization code was returned."
            case let .providerError(error):
                "Authorization denied: \(error)"
            }
        }
    }

    static let callbackPath = "/oauth/callback"
    private static let callbackTimeout: TimeInterval = 5 * 60

    private var server: HTTPServer?
    private var serverTask: Task<Void, Error>?
    private var callbackContinuation: CheckedContinuation<Callback, Error>?
    private var timeoutTask: Task<Void, Never>?
    private var completedResult: Result<Callback, Error>?
    private var didComplete = false
    private var expectedState = ""
    private(set) var port: UInt16 = 0

    var redirectURI: String {
        guard port > 0 else {
            preconditionFailure("redirectURI requested before the listener is ready")
        }
        return "http://127.0.0.1:\(port)\(Self.callbackPath)"
    }

    /// Starts listening on IPv4 loopback with an OS-assigned ephemeral port.
    /// Must complete before building the authorization URL so the redirect URI is known.
    func start(expectedState: String) async throws {
        guard server == nil else { return }
        let trimmedState = expectedState.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedState.isEmpty else {
            throw LoopbackError.failedToStart
        }
        self.expectedState = trimmedState

        do {
            let address = try sockaddr_in.inet(ip4: "127.0.0.1", port: 0)
            let handler = LoopbackHTTPHandler { [weak self] request in
                guard let self else {
                    return Self.htmlResponse(status: .serviceUnavailable, succeeded: false)
                }
                return await self.handle(request)
            }
            let config = HTTPServer.Configuration(address: address, logger: .disabled)
            let server = HTTPServer(config: config, handler: handler)
            self.server = server
            let serverTask = Task {
                try await server.run()
            }
            self.serverTask = serverTask
            try await server.waitUntilListening(timeout: 5)

            guard case let .ip4(address, assignedPort) = await server.listeningAddress,
                  address == "127.0.0.1",
                  assignedPort > 0
            else {
                await stop()
                throw LoopbackError.failedToStart
            }
            port = assignedPort
            Log.info("OAuth loopback listening on 127.0.0.1:\(port)")
        } catch {
            await stop()
            Log.error("OAuth loopback failed to bind: \(error.localizedDescription)")
            throw LoopbackError.failedToStart
        }
    }

    /// Waits for the browser to hit the redirect URI and returns the code once.
    func waitForCallback(timeout: TimeInterval = LoopbackServer.callbackTimeout) async throws -> Callback {
        do {
            let callback = try await waitForCallbackResult(timeout: timeout)
            await stop()
            return callback
        } catch {
            await stop()
            throw error
        }
    }

    func stop() async {
        timeoutTask?.cancel()
        timeoutTask = nil

        if !didComplete {
            didComplete = true
            let continuation = callbackContinuation
            callbackContinuation = nil
            continuation?.resume(throwing: LoopbackError.cancelled)
        }

        let server = self.server
        let serverTask = self.serverTask
        self.server = nil
        self.serverTask = nil
        port = 0

        await server?.stop(timeout: 0)
        serverTask?.cancel()
        _ = try? await serverTask?.value
    }

    private func waitForCallbackResult(timeout: TimeInterval) async throws -> Callback {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Callback, Error>) in
                Task { self.installCallbackContinuation(continuation, timeout: timeout) }
            }
        } onCancel: {
            Task { await self.complete(.failure(LoopbackError.cancelled)) }
        }
    }

    private func installCallbackContinuation(
        _ continuation: CheckedContinuation<Callback, Error>,
        timeout: TimeInterval
    ) {
        if let result = completedResult {
            completedResult = nil
            continuation.resume(with: result)
            return
        }

        callbackContinuation = continuation
        let clampedTimeout = max(timeout, 0)
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self] in
            let nanoseconds = UInt64(clampedTimeout * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            await self?.complete(.failure(LoopbackError.timedOut))
        }
    }

    private func handle(_ request: HTTPRequest) async -> HTTPResponse {
        guard request.path == Self.callbackPath else {
            return Self.htmlResponse(status: .notFound, succeeded: false)
        }
        guard request.method == .GET else {
            return Self.htmlResponse(status: .methodNotAllowed, succeeded: false)
        }

        let outcome = callbackOutcome(from: request.query)
        let accepted = complete(outcome.result)
        return Self.htmlResponse(
            status: outcome.responseStatus,
            succeeded: accepted && outcome.succeeded
        )
    }

    private func callbackOutcome(from query: [HTTPRequest.QueryItem]) -> CallbackOutcome {
        guard let state = query["state"], !state.isEmpty else {
            return .rejected(.missingState)
        }
        guard state == expectedState else {
            return .rejected(.stateMismatch)
        }
        if let error = query["error"], !error.isEmpty {
            return .rejected(.providerError(Self.sanitizedProviderError(error)))
        }
        guard let code = query["code"], !code.isEmpty else {
            return .rejected(.missingCode)
        }
        return .accepted(Callback(code: code))
    }

    @discardableResult
    private func complete(_ result: Result<Callback, Error>) -> Bool {
        guard !didComplete else { return false }
        didComplete = true
        timeoutTask?.cancel()
        timeoutTask = nil

        if let continuation = callbackContinuation {
            callbackContinuation = nil
            continuation.resume(with: result)
        } else {
            completedResult = result
        }
        return true
    }

    private static func htmlResponse(status: HTTPStatusCode, succeeded: Bool) -> HTTPResponse {
        let title = succeeded ? "Mailbell connected" : "Mailbell error"
        let body = succeeded
            ? "You can close this tab and return to Mailbell."
            : "Authorization failed. Please try again from Mailbell."
        let html = """
        <!doctype html><html><head><meta charset="utf-8"><title>\(title)</title></head>
        <body style="font-family:-apple-system,sans-serif;text-align:center;padding-top:80px">
        <h2>\(title)</h2><p>\(body)</p></body></html>
        """
        return HTTPResponse(
            statusCode: status,
            headers: [.contentType: "text/html; charset=utf-8"],
            body: Data(html.utf8)
        )
    }

    private static func sanitizedProviderError(_ rawError: String) -> String {
        let trimmed = rawError.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-")
        guard !trimmed.isEmpty,
              trimmed.count <= 80,
              trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) })
        else {
            return "provider_error"
        }
        return trimmed
    }
}

private struct CallbackOutcome {
    let result: Result<LoopbackServer.Callback, Error>
    let responseStatus: HTTPStatusCode
    let succeeded: Bool

    static func accepted(_ callback: LoopbackServer.Callback) -> CallbackOutcome {
        CallbackOutcome(result: .success(callback), responseStatus: .ok, succeeded: true)
    }

    static func rejected(_ error: LoopbackServer.LoopbackError) -> CallbackOutcome {
        CallbackOutcome(result: .failure(error), responseStatus: .badRequest, succeeded: false)
    }
}

private struct LoopbackHTTPHandler: HTTPHandler {
    let handle: @Sendable (HTTPRequest) async -> HTTPResponse

    func handleRequest(_ request: HTTPRequest) async throws -> HTTPResponse {
        await handle(request)
    }
}
