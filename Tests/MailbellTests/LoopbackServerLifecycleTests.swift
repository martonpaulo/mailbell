@testable import mailbell
import XCTest

/// Starting, stopping and restarting the loopback listener: a timed-out wait
/// must release the port, and a restarted server must not replay a callback
/// from the run before it.
final class LoopbackServerLifecycleTests: XCTestCase {
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

        await assertAsyncThrows {
            try await waitTask.value
        } validate: { error in
            XCTAssertEqual(error as? LoopbackServer.LoopbackError, .cancelled)
        }
        try await assertRequestFailsAfterStop(redirectURI: redirectURI)
    }

    func testStopCancelsPendingCallbackWait() async throws {
        let server = try await startedServer()
        let waitTask = Task { try await server.waitForCallback(timeout: 2) }
        try await Task.sleep(nanoseconds: 10_000_000)

        await server.stop()

        await assertAsyncThrows {
            try await waitTask.value
        } validate: { error in
            XCTAssertEqual(error as? LoopbackServer.LoopbackError, .cancelled)
            XCTAssertEqual(error.localizedDescription, "Google sign-in was cancelled.")
        }
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

        await assertAsyncThrows {
            try await staleWaitTask.value
        } validate: { error in
            XCTAssertEqual(error as? LoopbackServer.LoopbackError, .cancelled)
        }

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

    private func assertAsyncThrows(
        _ operation: () async throws -> some Any,
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
