@testable import mailbell
import Foundation
import XCTest

final class LoopbackServerTests: XCTestCase {
    func testStartsOnIPv4LoopbackWithCallbackPath() async throws {
        let server = LoopbackServer()
        try await server.start(expectedState: "state-value")

        let redirectURI = await server.redirectURI

        XCTAssertTrue(redirectURI.hasPrefix("http://127.0.0.1:"))
        XCTAssertTrue(redirectURI.hasSuffix(LoopbackServer.callbackPath))
        let port = await server.port
        XCTAssertGreaterThan(port, 0)
        await server.stop()
    }

    func testValidCallbackReturnsCodeOnce() async throws {
        let server = try await startedServer()
        let waitTask = Task { try await server.waitForCallback(timeout: 2) }

        let response = try await request(server, query: "code=abc123&state=state-value")
        let callback = try await waitTask.value

        XCTAssertEqual(response.statusCode, 200)
        XCTAssertTrue(response.body.contains("Mailbell connected"))
        XCTAssertTrue(response.body.contains("data-state=\"success\""))
        XCTAssertTrue(response.body.contains(":root[data-state=\"success\"]"))
        XCTAssertTrue(response.body.contains("--state-accent: #248a3d"))
        XCTAssertTrue(response.body.contains("background: var(--state-accent)"))
        XCTAssertTrue(response.body.contains("data:image/png;base64,"))
        XCTAssertTrue(response.body.contains("aria-labelledby=\"page-title\""))
        XCTAssertTrue(response.body.contains("prefers-color-scheme: dark"))
        XCTAssertFalse(response.body.contains("abc123"))
        XCTAssertFalse(response.body.contains("state-value"))
        XCTAssertEqual(callback.code, "abc123")
    }

    func testPercentEncodedCodeAndStateAreDecoded() async throws {
        let state = "state value/with symbols"
        let server = try await startedServer(expectedState: state)
        let waitTask = Task { try await server.waitForCallback(timeout: 2) }

        _ = try await request(
            server,
            query: "code=abc%20123%2Fok&state=state%20value%2Fwith%20symbols"
        )
        let callback = try await waitTask.value

        XCTAssertEqual(callback.code, "abc 123/ok")
    }

    func testMissingStateFailsSecurely() async throws {
        let server = try await startedServer()
        let waitTask = Task { try await server.waitForCallback(timeout: 2) }

        let response = try await request(server, query: "code=abc123")

        XCTAssertEqual(response.statusCode, 400)
        XCTAssertTrue(response.body.contains("The sign-in session expired"))
        XCTAssertTrue(response.body.contains("Start sign-in again from Mailbell"))
        XCTAssertFalse(response.body.contains("abc123"))
        await assertAsyncThrows({ try await waitTask.value }, validate: { error in
            XCTAssertEqual(error as? LoopbackServer.LoopbackError, .missingState)
        })
    }

    func testMismatchedStateFailsSecurely() async throws {
        let server = try await startedServer()
        let waitTask = Task { try await server.waitForCallback(timeout: 2) }

        let response = try await request(server, query: "code=abc123&state=raw-state-token")

        XCTAssertEqual(response.statusCode, 400)
        XCTAssertTrue(response.body.contains("The sign-in session changed"))
        XCTAssertFalse(response.body.contains("abc123"))
        XCTAssertFalse(response.body.contains("raw-state-token"))
        await assertAsyncThrows({ try await waitTask.value }, validate: { error in
            XCTAssertEqual(error as? LoopbackServer.LoopbackError, .stateMismatch)
        })
    }

    func testProviderErrorIsSanitizedAndTyped() async throws {
        let server = try await startedServer()
        let waitTask = Task { try await server.waitForCallback(timeout: 2) }

        let response = try await request(server, query: "error=access_denied&state=state-value")

        XCTAssertEqual(response.statusCode, 400)
        XCTAssertTrue(response.body.contains("Mailbell could not connect"))
        XCTAssertTrue(response.body.contains("data-state=\"error\""))
        XCTAssertTrue(response.body.contains("--state-accent: #d70015"))
        XCTAssertTrue(response.body.contains("Permission was not granted"))
        XCTAssertTrue(response.body.contains("Google prompt is cancelled or the permission is denied"))
        XCTAssertTrue(
            response.body.contains("--state-bar: linear-gradient(90deg, #ff3b30 0%, #ff453a 52%, #ff9f0a 100%)")
        )
        XCTAssertFalse(response.body.contains("access_denied"))
        XCTAssertFalse(response.body.contains("Provider code"))
        XCTAssertFalse(response.body.contains("state-value"))
        await assertAsyncThrows({ try await waitTask.value }, validate: { error in
            XCTAssertEqual(error as? LoopbackServer.LoopbackError, .providerError("access_denied"))
            XCTAssertFalse(error.localizedDescription.contains("state-value"))
        })
    }

    func testMissingCodeFailsAfterMatchingState() async throws {
        let server = try await startedServer()
        let waitTask = Task { try await server.waitForCallback(timeout: 2) }

        let response = try await request(server, query: "state=state-value")

        XCTAssertEqual(response.statusCode, 400)
        XCTAssertTrue(response.body.contains("Google sign-in did not finish"))
        XCTAssertFalse(response.body.contains("state-value"))
        await assertAsyncThrows({ try await waitTask.value }, validate: { error in
            XCTAssertEqual(error as? LoopbackServer.LoopbackError, .missingCode)
        })
    }

    func testWrongPathAndMethodDoNotCompleteAuthorization() async throws {
        let server = try await startedServer()
        let waitTask = Task { try await server.waitForCallback(timeout: 30) }

        let wrongPath = try await request(server, path: "/favicon.ico", query: "code=abc123&state=state-value")
        let wrongMethod = try await request(server, method: "POST", query: "code=abc123&state=state-value")
        await server.stop()

        XCTAssertEqual(wrongPath.statusCode, 404)
        XCTAssertEqual(wrongMethod.statusCode, 405)
        XCTAssertTrue(wrongPath.body.contains("data-state=\"error\""))
        XCTAssertTrue(wrongMethod.body.contains("data-state=\"error\""))
        XCTAssertTrue(wrongPath.body.contains("This sign-in page is not available"))
        XCTAssertTrue(wrongMethod.body.contains("This sign-in request is not supported"))
        await assertAsyncThrows({ try await waitTask.value }, validate: { error in
            XCTAssertEqual(error as? LoopbackServer.LoopbackError, .cancelled)
        })
    }

    func testDuplicateConcurrentCallbacksCannotResumeTwice() async throws {
        let server = try await startedServer()
        let waitTask = Task { try await server.waitForCallback(timeout: 2) }

        let firstURL = try await callbackURL(server, query: "code=first&state=state-value")
        let secondURL = try await callbackURL(server, query: "code=second&state=state-value")
        async let first = Self.request(url: firstURL)
        async let second = Self.request(url: secondURL)
        let responses = try await [first, second]
        let callback = try await waitTask.value

        XCTAssertTrue(["first", "second"].contains(callback.code))
        XCTAssertEqual(responses.map(\.statusCode), [200, 200])
    }

    func testWaitForCallbackTimesOutAndStopsListener() async throws {
        let server = try await startedServer()
        let redirectURI = await server.redirectURI

        do {
            _ = try await server.waitForCallback(timeout: 0)
            XCTFail("Expected OAuth callback wait to time out.")
        } catch let error as LoopbackServer.LoopbackError {
            XCTAssertEqual(error, .timedOut)
            XCTAssertEqual(error.localizedDescription, "Google sign-in timed out. Try again from Mailbell.")
        }

        try await assertRequestFailsAfterStop(redirectURI: redirectURI)
    }

    func testCancellationStopsListener() async throws {
        let server = try await startedServer()
        let redirectURI = await server.redirectURI
        let waitTask = Task { try await server.waitForCallback(timeout: 30) }

        waitTask.cancel()

        await assertAsyncThrows({ try await waitTask.value }, validate: { error in
            XCTAssertEqual(error as? LoopbackServer.LoopbackError, .cancelled)
        })
        try await assertRequestFailsAfterStop(redirectURI: redirectURI)
    }

    func testStopCancelsPendingCallbackWait() async throws {
        let server = try await startedServer()
        let waitTask = Task { try await server.waitForCallback(timeout: 2) }
        try await Task.sleep(nanoseconds: 10_000_000)

        await server.stop()

        await assertAsyncThrows({ try await waitTask.value }, validate: { error in
            XCTAssertEqual(error as? LoopbackServer.LoopbackError, .cancelled)
            XCTAssertEqual(error.localizedDescription, "Google sign-in was cancelled.")
        })
    }

    func testCanRestartAfterCallbackTimeout() async throws {
        let server = try await startedServer()

        do {
            _ = try await server.waitForCallback(timeout: 0)
            XCTFail("Expected OAuth callback wait to time out.")
        } catch let error as LoopbackServer.LoopbackError {
            XCTAssertEqual(error, .timedOut)
        }

        try await server.start(expectedState: "state-value")
        let waitTask = Task { try await server.waitForCallback(timeout: 2) }

        _ = try await request(server, query: "code=fresh-code&state=state-value")
        let callback = try await waitTask.value

        XCTAssertEqual(callback.code, "fresh-code")
    }

    func testRestartDoesNotReplayPendingCallbackFromPreviousRun() async throws {
        let server = try await startedServer()
        _ = try await request(server, query: "code=stale-code&state=state-value")
        await server.stop()

        try await server.start(expectedState: "state-value")

        do {
            _ = try await server.waitForCallback(timeout: 0)
            XCTFail("Expected stale callback state to be cleared before restart.")
        } catch let error as LoopbackServer.LoopbackError {
            XCTAssertEqual(error, .timedOut)
        }
    }

    func testCancelledPreviousWaitCannotStopRestartedServer() async throws {
        let server = try await startedServer()
        let staleWaitTask = Task { try await server.waitForCallback(timeout: 30) }
        try await Task.sleep(nanoseconds: 10_000_000)

        await server.stop()
        try await server.start(expectedState: "state-value")

        await assertAsyncThrows({ try await staleWaitTask.value }, validate: { error in
            XCTAssertEqual(error as? LoopbackServer.LoopbackError, .cancelled)
        })

        let freshWaitTask = Task { try await server.waitForCallback(timeout: 2) }
        _ = try await request(server, query: "code=fresh-code&state=state-value")
        let callback = try await freshWaitTask.value

        XCTAssertEqual(callback.code, "fresh-code")
    }

    private func startedServer(expectedState: String = "state-value") async throws -> LoopbackServer {
        let server = LoopbackServer()
        try await server.start(expectedState: expectedState)
        return server
    }

    private func request(
        _ server: LoopbackServer,
        method: String = "GET",
        path: String? = nil,
        query: String
    ) async throws -> (statusCode: Int, body: String) {
        let url = try await callbackURL(server, path: path, query: query)
        return try await Self.request(url: url, method: method)
    }

    private func callbackURL(
        _ server: LoopbackServer,
        path: String? = nil,
        query: String
    ) async throws -> URL {
        let redirectURI = await server.redirectURI
        var components = try XCTUnwrap(URLComponents(string: redirectURI))
        if let path {
            components.path = path
        }
        components.percentEncodedQuery = query
        return try XCTUnwrap(components.url)
    }

    private static func request(url: URL, method: String = "GET") async throws -> (statusCode: Int, body: String) {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 2
        let (data, response) = try await URLSession.shared.data(for: request)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        return (http.statusCode, String(data: data, encoding: .utf8) ?? "")
    }

    private func assertRequestFailsAfterStop(redirectURI: String) async throws {
        let url = try XCTUnwrap(URL(string: redirectURI + "?code=abc123&state=state-value"))
        do {
            _ = try await Self.request(url: url)
            XCTFail("Expected stopped loopback listener to reject new requests.")
        } catch {
            XCTAssertTrue(error is URLError || "\(type(of: error))".contains("XCT"))
        }
    }

    private func assertAsyncThrows<T>(
        _ operation: () async throws -> T,
        validate: (Error) -> Void
    ) async {
        do {
            _ = try await operation()
            XCTFail("Expected operation to throw.")
        } catch {
            validate(error)
        }
    }
}
