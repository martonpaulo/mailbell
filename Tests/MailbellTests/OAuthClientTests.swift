@testable import mailbell
import XCTest

final class OAuthClientTests: XCTestCase {
    func testTokenEndpointDetailOmitsRawResponseDescriptionAndSecrets() {
        let description = [
            "client_secret=secret-value",
            "refresh_token=refresh-value",
            "access_token=access-value",
            "code=oauth-code"
        ].joined(separator: " ")
        let body = """
        {
          "error": "invalid_grant",
          "error_description": "\(description)"
        }
        """

        let detail = OAuthClient.sanitizedTokenEndpointDetail(statusCode: 400, body: body)

        XCTAssertEqual(detail, "OAuth token endpoint returned invalid_grant (HTTP 400).")
        XCTAssertFalse(detail.contains("secret-value"))
        XCTAssertFalse(detail.contains("refresh-value"))
        XCTAssertFalse(detail.contains("access-value"))
        XCTAssertFalse(detail.contains("oauth-code"))
    }

    func testTokenEndpointDetailFallsBackToStatusOnlyForNonJSONBody() {
        let detail = OAuthClient.sanitizedTokenEndpointDetail(
            statusCode: 500,
            body: "server client_secret=secret-value"
        )

        XCTAssertEqual(detail, "OAuth token endpoint returned HTTP 500.")
        XCTAssertFalse(detail.contains("secret-value"))
    }

    func testTokenEndpointDetailDoesNotEchoUnexpectedErrorCodeText() {
        let detail = OAuthClient.sanitizedTokenEndpointDetail(
            statusCode: 400,
            body: #"{"error":"invalid_grant client_secret=secret-value"}"#
        )

        XCTAssertEqual(detail, "OAuth token endpoint returned HTTP 400.")
        XCTAssertFalse(detail.contains("secret-value"))
        XCTAssertFalse(detail.contains("invalid_grant client_secret"))
    }

    func testUserInfoEndpointDetailUsesStatusOnly() {
        let detail = OAuthClient.sanitizedUserInfoDetail(statusCode: 429)

        XCTAssertEqual(detail, "OpenID UserInfo endpoint returned HTTP 429.")
        XCTAssertFalse(detail.contains("access_token"))
        XCTAssertFalse(detail.contains("Bearer"))
    }
}
