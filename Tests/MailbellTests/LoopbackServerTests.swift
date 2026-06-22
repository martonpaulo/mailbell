@testable import mailbell
import Foundation
import XCTest

final class LoopbackServerTests: XCTestCase {
    func testParsesOAuthCallbackRequestLine() throws {
        let items = try XCTUnwrap(
            LoopbackServer.callbackQueryItems(from: "GET /?code=abc123&state=state-value HTTP/1.1")
        )

        XCTAssertEqual(items.first(where: { $0.name == "code" })?.value, "abc123")
        XCTAssertEqual(items.first(where: { $0.name == "state" })?.value, "state-value")
    }

    func testParsesOAuthErrorCallbackRequestLine() throws {
        let items = try XCTUnwrap(
            LoopbackServer.callbackQueryItems(from: "GET /?error=access_denied&state=state-value HTTP/1.1")
        )

        XCTAssertEqual(items.first(where: { $0.name == "error" })?.value, "access_denied")
        XCTAssertEqual(items.first(where: { $0.name == "state" })?.value, "state-value")
    }

    func testIgnoresRequestLinesWithoutOAuthResult() {
        XCTAssertNil(LoopbackServer.callbackQueryItems(from: "GET /favicon.ico HTTP/1.1"))
        XCTAssertNil(LoopbackServer.callbackQueryItems(from: "GET /?state=state-value HTTP/1.1"))
        XCTAssertNil(LoopbackServer.callbackQueryItems(from: "invalid"))
    }

    func testWaitForCallbackTimesOutWhenBrowserNeverReturns() async {
        let server = LoopbackServer()

        do {
            _ = try await server.waitForCallback(timeout: 0)
            XCTFail("Expected OAuth callback wait to time out.")
        } catch let error as LoopbackServer.LoopbackError {
            XCTAssertEqual(error, .timedOut)
            XCTAssertEqual(error.localizedDescription, "Google sign-in timed out. Try again from Mailbell.")
        } catch {
            XCTFail("Expected LoopbackError.timedOut, got \(error).")
        }
    }

    func testStopCancelsPendingCallbackWait() async throws {
        let server = LoopbackServer()
        try await server.start()
        let waitTask = Task { try await server.waitForCallback(timeout: 2) }
        try await Task.sleep(nanoseconds: 10_000_000)

        server.stop()

        do {
            _ = try await waitTask.value
            XCTFail("Expected stopped loopback server to cancel the pending wait.")
        } catch let error as LoopbackServer.LoopbackError {
            XCTAssertEqual(error, .cancelled)
            XCTAssertEqual(error.localizedDescription, "Google sign-in was cancelled.")
        } catch {
            XCTFail("Expected LoopbackError.cancelled, got \(error).")
        }
    }

    func testCanRestartAfterCallbackTimeout() async throws {
        let server = LoopbackServer()
        try await server.start()

        do {
            _ = try await server.waitForCallback(timeout: 0)
            XCTFail("Expected OAuth callback wait to time out.")
        } catch let error as LoopbackServer.LoopbackError {
            XCTAssertEqual(error, .timedOut)
        }

        server.stop()
        try await server.start()
        let waitTask = Task { try await server.waitForCallback(timeout: 2) }

        _ = try await request(server, query: "code=fresh-code&state=state-value")
        let items = try await waitTask.value

        XCTAssertEqual(items.first(where: { $0.name == "code" })?.value, "fresh-code")
        server.stop()
    }

    func testRestartDoesNotReplayPendingCallbackFromPreviousRun() async throws {
        let server = LoopbackServer()
        try await server.start()
        _ = try await request(server, query: "code=stale-code&state=state-value")
        server.stop()

        try await server.start()

        do {
            _ = try await server.waitForCallback(timeout: 0)
            XCTFail("Expected stale callback state to be cleared before restart.")
        } catch let error as LoopbackServer.LoopbackError {
            XCTAssertEqual(error, .timedOut)
        }

        server.stop()
    }

    private func request(_ server: LoopbackServer, query: String) async throws -> (statusCode: Int, body: String) {
        var components = try XCTUnwrap(URLComponents(string: server.redirectURI))
        components.percentEncodedQuery = query
        let url = try XCTUnwrap(components.url)
        let (data, response) = try await URLSession.shared.data(from: url)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        return (http.statusCode, String(data: data, encoding: .utf8) ?? "")
    }
}
