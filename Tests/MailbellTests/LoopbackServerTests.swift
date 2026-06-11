@testable import mailbell
import XCTest

final class LoopbackServerTests: XCTestCase {
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
