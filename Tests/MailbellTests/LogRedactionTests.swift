@testable import mailbell
import XCTest

final class LogRedactionTests: XCTestCase {
    func testRedactsOAuthSecretsAndBearerValues() {
        let message = [
            "access_token=access-value",
            #"refresh_token: "refresh-value""#,
            "client_secret=secret-value",
            "code_verifier=verifier-value",
            "code=oauth-code",
            "Authorization: Bearer ya29.token-value"
        ].joined(separator: " ")

        let redacted = Log.redact(message)

        XCTAssertFalse(redacted.contains("access-value"))
        XCTAssertFalse(redacted.contains("refresh-value"))
        XCTAssertFalse(redacted.contains("secret-value"))
        XCTAssertFalse(redacted.contains("verifier-value"))
        XCTAssertFalse(redacted.contains("oauth-code"))
        XCTAssertFalse(redacted.contains("ya29.token-value"))
        XCTAssertTrue(redacted.contains("access_token=<redacted>"))
        XCTAssertTrue(redacted.contains("Bearer <redacted>"))
    }
}
