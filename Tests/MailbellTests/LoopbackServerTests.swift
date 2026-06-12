@testable import mailbell
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
}
