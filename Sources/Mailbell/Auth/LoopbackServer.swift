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
    private var callbackRunID = 0
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

        beginNewCallbackRun()
        self.expectedState = trimmedState
        let callbackRunID = self.callbackRunID

        do {
            let address = try sockaddr_in.inet(ip4: "127.0.0.1", port: 0)
            let handler = LoopbackHTTPHandler { [weak self, callbackRunID] request in
                guard let self else {
                    return Self.htmlResponse(status: .serviceUnavailable, state: .error(.serverUnavailable))
                }
                return await self.handle(request, callbackRunID: callbackRunID)
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
        let callbackRunID = self.callbackRunID
        do {
            let callback = try await waitForCallbackResult(timeout: timeout, callbackRunID: callbackRunID)
            await stop(callbackRunID: callbackRunID)
            return callback
        } catch {
            await stop(callbackRunID: callbackRunID)
            throw error
        }
    }

    func stop() async {
        await stop(callbackRunID: nil)
    }

    private func stop(callbackRunID expectedRunID: Int?) async {
        if let expectedRunID, expectedRunID != callbackRunID {
            return
        }

        callbackRunID += 1
        timeoutTask?.cancel()
        timeoutTask = nil

        if !didComplete {
            didComplete = true
            let continuation = callbackContinuation
            callbackContinuation = nil
            continuation?.resume(throwing: LoopbackError.cancelled)
        } else {
            callbackContinuation = nil
        }
        completedResult = nil

        let server = self.server
        let serverTask = self.serverTask
        self.server = nil
        self.serverTask = nil
        port = 0

        await server?.stop(timeout: 0)
        serverTask?.cancel()
        _ = try? await serverTask?.value
    }

    private func waitForCallbackResult(timeout: TimeInterval, callbackRunID: Int) async throws -> Callback {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Callback, Error>) in
                Task {
                    self.installCallbackContinuation(
                        continuation,
                        timeout: timeout,
                        callbackRunID: callbackRunID
                    )
                }
            }
        } onCancel: {
            Task { await self.complete(.failure(LoopbackError.cancelled), callbackRunID: callbackRunID) }
        }
    }

    private func installCallbackContinuation(
        _ continuation: CheckedContinuation<Callback, Error>,
        timeout: TimeInterval,
        callbackRunID: Int
    ) {
        guard callbackRunID == self.callbackRunID else {
            continuation.resume(throwing: LoopbackError.cancelled)
            return
        }

        if let result = completedResult {
            completedResult = nil
            continuation.resume(with: result)
            return
        }

        callbackContinuation = continuation
        let clampedTimeout = max(timeout, 0)
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self, callbackRunID] in
            let nanoseconds = UInt64(clampedTimeout * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            await self?.complete(.failure(LoopbackError.timedOut), callbackRunID: callbackRunID)
        }
    }

    private func handle(_ request: HTTPRequest, callbackRunID: Int) async -> HTTPResponse {
        guard request.path == Self.callbackPath else {
            return Self.htmlResponse(status: .notFound, state: .error(.unexpectedPath))
        }
        guard request.method == .GET else {
            return Self.htmlResponse(status: .methodNotAllowed, state: .error(.unsupportedMethod))
        }

        let outcome = callbackOutcome(from: request.query)
        let accepted = complete(outcome.result, callbackRunID: callbackRunID)
        return Self.htmlResponse(
            status: outcome.responseStatus,
            state: accepted ? outcome.pageState : .error(.alreadyHandled)
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
    private func complete(_ result: Result<Callback, Error>, callbackRunID: Int) -> Bool {
        guard callbackRunID == self.callbackRunID, !didComplete else { return false }
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

    private func beginNewCallbackRun() {
        callbackRunID += 1
        timeoutTask?.cancel()
        timeoutTask = nil
        let continuation = callbackContinuation
        callbackContinuation = nil
        completedResult = nil
        didComplete = false
        continuation?.resume(throwing: LoopbackError.cancelled)
    }

    private static func htmlResponse(status: HTTPStatusCode, state: LoopbackCallbackPage.State) -> HTTPResponse {
        let html = LoopbackCallbackPage.html(state: state)
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
    let pageState: LoopbackCallbackPage.State

    static func accepted(_ callback: LoopbackServer.Callback) -> CallbackOutcome {
        CallbackOutcome(result: .success(callback), responseStatus: .ok, pageState: .success)
    }

    static func rejected(_ error: LoopbackServer.LoopbackError) -> CallbackOutcome {
        CallbackOutcome(
            result: .failure(error),
            responseStatus: .badRequest,
            pageState: .error(error.callbackPageReason)
        )
    }
}

private extension LoopbackServer.LoopbackError {
    var callbackPageReason: LoopbackCallbackPage.ErrorReason {
        switch self {
        case .failedToStart, .timedOut, .cancelled:
            .serverUnavailable
        case .missingState:
            .missingState
        case .stateMismatch:
            .stateMismatch
        case .missingCode:
            .missingCode
        case let .providerError(error):
            .providerError(error)
        }
    }
}

private struct LoopbackHTTPHandler: HTTPHandler {
    let handle: @Sendable (HTTPRequest) async -> HTTPResponse

    func handleRequest(_ request: HTTPRequest) async throws -> HTTPResponse {
        await handle(request)
    }
}
