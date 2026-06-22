@testable import mailbell
import XCTest

final class OAuthConfigTests: XCTestCase {
    private let clientID = "dummy-local-client-id.apps.googleusercontent.com"
    private let clientSecret = "dummy-local-client-secret"

    func testLoadsCredentialsFromEnvironment() throws {
        let config = try OAuthConfig.load(
            environment: [
                OAuthConfig.clientIDKey: clientID,
                OAuthConfig.clientSecretKey: clientSecret
            ]
        )

        XCTAssertEqual(config.clientID, clientID)
        XCTAssertEqual(config.clientSecret, clientSecret)
    }

    func testLoadsDesktopClientIDWithoutClientSecret() throws {
        let config = try OAuthConfig.load(
            environment: [
                OAuthConfig.clientIDKey: clientID
            ]
        )

        XCTAssertEqual(config.clientID, clientID)
        XCTAssertNil(config.clientSecret)
    }

    func testBlankClientSecretIsTreatedAsAbsent() throws {
        let config = try OAuthConfig.load(
            environment: [
                OAuthConfig.clientIDKey: clientID,
                OAuthConfig.clientSecretKey: "   "
            ]
        )

        XCTAssertEqual(config.clientID, clientID)
        XCTAssertNil(config.clientSecret)
    }

    func testRejectsMissingCredentials() {
        XCTAssertThrowsError(try OAuthConfig.load(environment: [:])) { error in
            XCTAssertEqual(error as? OAuthConfigIssue, .missingCredentials)
        }
    }

    func testRejectsMalformedClientID() {
        XCTAssertThrowsError(
            try OAuthConfig.load(
                environment: [
                    OAuthConfig.clientIDKey: "not-a-google-client-id",
                    OAuthConfig.clientSecretKey: clientSecret
                ]
            )
        ) { error in
            XCTAssertEqual(error as? OAuthConfigIssue, .invalidClientID)
        }
    }

    func testExplicitInvalidEnvironmentDoesNotFallBackToDotEnv() {
        XCTAssertThrowsError(
            try OAuthConfig.load(
                environment: [
                    OAuthConfig.clientIDKey: "not-a-google-client-id",
                    OAuthConfig.clientSecretKey: clientSecret
                ],
                dotEnv: [
                    OAuthConfig.clientIDKey: clientID,
                    OAuthConfig.clientSecretKey: clientSecret
                ]
            )
        ) { error in
            XCTAssertEqual(error as? OAuthConfigIssue, .invalidClientID)
        }
    }

    func testEnvironmentClientIDDoesNotCombineDotEnvSecret() throws {
        let config = try OAuthConfig.load(
            environment: [
                OAuthConfig.clientIDKey: clientID
            ],
            dotEnv: [
                OAuthConfig.clientIDKey: "other-client-id.apps.googleusercontent.com",
                OAuthConfig.clientSecretKey: clientSecret
            ]
        )

        XCTAssertEqual(config.clientID, clientID)
        XCTAssertNil(config.clientSecret)
    }

    func testSecretWithoutClientIDDoesNotFallBackToDotEnvClientID() {
        XCTAssertThrowsError(
            try OAuthConfig.load(
                environment: [
                    OAuthConfig.clientSecretKey: clientSecret
                ],
                dotEnv: [
                    OAuthConfig.clientIDKey: clientID
                ]
            )
        ) { error in
            XCTAssertEqual(error as? OAuthConfigIssue, .missingCredentials)
        }
    }
}
