@testable import mailbell
import XCTest

final class OAuthConfigTests: XCTestCase {
    private struct InjectorResult {
        let status: Int32
        let stdout: String
        let stderr: String
    }

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

    func testInjectorWritesExpectedBundleKeysWithDummyCredentials() throws {
        let root = repositoryRoot()
        let plistURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MailbellInfo.\(UUID().uuidString).plist")
        let initialPlist = [
            "CFBundleIdentifier": "com.example.old",
            "CFBundleName": "Old",
            "CFBundleDisplayName": "Old"
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: initialPlist, format: .xml, options: 0)
        try data.write(to: plistURL)
        defer { try? FileManager.default.removeItem(at: plistURL) }

        let result = runInjector(
            root: root,
            arguments: [plistURL.path],
            environment: [
                OAuthConfig.clientIDKey: clientID,
                OAuthConfig.clientSecretKey: clientSecret,
                "MAILBELL_BUNDLE_ID": "dev.example.mailbell",
                "MAILBELL_APP_DISPLAY_NAME": "Mailbell"
            ]
        )

        XCTAssertEqual(result.status, 0, result.stderr)
        let updatedData = try Data(contentsOf: plistURL)
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: updatedData, format: nil) as? [String: String]
        )
        XCTAssertEqual(plist["MailbellGoogleClientID"], clientID)
        XCTAssertEqual(plist["MailbellGoogleClientSecret"], clientSecret)
        XCTAssertEqual(plist["CFBundleIdentifier"], "dev.example.mailbell")
        XCTAssertEqual(plist["CFBundleName"], "Mailbell")
        XCTAssertEqual(plist["CFBundleDisplayName"], "Mailbell")
    }

    func testInjectorReadsBundleIdentityFromDotEnv() throws {
        let root = repositoryRoot()
        let plistURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MailbellInfo.\(UUID().uuidString).plist")
        let dotenvURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MailbellEnv.\(UUID().uuidString)")
        let initialPlist = [
            "CFBundleIdentifier": "com.example.old",
            "CFBundleName": "Old",
            "CFBundleDisplayName": "Old"
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: initialPlist, format: .xml, options: 0)
        try data.write(to: plistURL)
        let dotenv = """
        \(OAuthConfig.clientIDKey)=\(clientID)
        \(OAuthConfig.clientSecretKey)=\(clientSecret)
        MAILBELL_BUNDLE_ID=dev.dotenv.mailbell
        MAILBELL_APP_DISPLAY_NAME=Mailbell Local
        """
        try dotenv.write(to: dotenvURL, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(at: plistURL)
            try? FileManager.default.removeItem(at: dotenvURL)
        }

        let result = runInjector(
            root: root,
            arguments: [plistURL.path],
            environment: [
                "MAILBELL_DOTENV_PATH": dotenvURL.path
            ]
        )

        XCTAssertEqual(result.status, 0, result.stderr)
        let updatedData = try Data(contentsOf: plistURL)
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: updatedData, format: nil) as? [String: String]
        )
        XCTAssertEqual(plist["CFBundleIdentifier"], "dev.dotenv.mailbell")
        XCTAssertEqual(plist["CFBundleName"], "Mailbell Local")
        XCTAssertEqual(plist["CFBundleDisplayName"], "Mailbell Local")
    }

    func testInjectorCheckFailsWithoutCredentials() {
        let result = runInjector(root: repositoryRoot(), arguments: ["--check"], environment: [:])

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.stderr.contains("set \(OAuthConfig.clientIDKey) and \(OAuthConfig.clientSecretKey)"))
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func runInjector(
        root: URL,
        arguments: [String],
        environment: [String: String]
    ) -> InjectorResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [root.appendingPathComponent("Scripts/inject_oauth_config.sh").path] + arguments
        process.currentDirectoryURL = root
        var processEnvironment = ProcessInfo.processInfo.environment
        processEnvironment.removeValue(forKey: OAuthConfig.clientIDKey)
        processEnvironment.removeValue(forKey: OAuthConfig.clientSecretKey)
        processEnvironment.removeValue(forKey: "MAILBELL_BUNDLE_ID")
        processEnvironment.removeValue(forKey: "MAILBELL_APP_DISPLAY_NAME")
        processEnvironment["MAILBELL_DOTENV_PATH"] = root.appendingPathComponent(".env.test-missing").path
        environment.forEach { processEnvironment[$0.key] = $0.value }
        process.environment = processEnvironment

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return InjectorResult(status: -1, stdout: "", stderr: error.localizedDescription)
        }

        return InjectorResult(
            status: process.terminationStatus,
            stdout: String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
            stderr: String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        )
    }
}
