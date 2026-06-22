@testable import mailbell
import XCTest

final class BundleConfigScriptTests: XCTestCase {
    private struct InjectorResult {
        let status: Int32
        let stdout: String
        let stderr: String
    }

    private let clientID = "dummy-local-client-id.apps.googleusercontent.com"
    private let clientSecret = "dummy-local-client-secret"

    func testWritesExpectedBundleKeysWithDummyCredentials() throws {
        let plistURL = try makePlist([
            "CFBundleIdentifier": "com.example.old",
            "CFBundleName": "Old",
            "CFBundleDisplayName": "Old"
        ])
        defer { try? FileManager.default.removeItem(at: plistURL) }

        let result = runInjector(
            arguments: [plistURL.path],
            environment: [
                OAuthConfig.clientIDKey: clientID,
                OAuthConfig.clientSecretKey: clientSecret,
                "MAILBELL_BUNDLE_ID": "dev.example.mailbell"
            ]
        )

        XCTAssertEqual(result.status, 0, result.stderr)
        let plist = try readStringPlist(plistURL)
        XCTAssertEqual(plist["MailbellGoogleClientID"], clientID)
        XCTAssertEqual(plist["MailbellGoogleClientSecret"], clientSecret)
        XCTAssertEqual(plist["CFBundleIdentifier"], "dev.example.mailbell")
        XCTAssertEqual(plist["CFBundleName"], "Mailbell")
        XCTAssertEqual(plist["CFBundleDisplayName"], "Mailbell")
    }

    func testWritesReleaseVersionAndBuildNumber() throws {
        let plistURL = try makePlist([
            "CFBundleIdentifier": "com.example.old",
            "CFBundleName": "Old",
            "CFBundleDisplayName": "Old",
            "CFBundleShortVersionString": "0.0.0",
            "CFBundleVersion": "0"
        ])
        defer { try? FileManager.default.removeItem(at: plistURL) }

        let result = runInjector(
            arguments: ["--version", "1.2.3", "--build-number", "456", plistURL.path],
            environment: [
                OAuthConfig.clientIDKey: clientID,
                "MAILBELL_BUNDLE_ID": "dev.example.mailbell"
            ]
        )

        XCTAssertEqual(result.status, 0, result.stderr)
        let plist = try readStringPlist(plistURL)
        XCTAssertEqual(plist["CFBundleShortVersionString"], "1.2.3")
        XCTAssertEqual(plist["CFBundleVersion"], "456")
        XCTAssertEqual(plist["CFBundleName"], "Mailbell")
        XCTAssertEqual(plist["CFBundleDisplayName"], "Mailbell")
    }

    func testOmitsBundleSecretKeyWhenSecretIsAbsent() throws {
        let plistURL = try makePlist([
            "CFBundleIdentifier": "com.example.old",
            "CFBundleName": "Old",
            "CFBundleDisplayName": "Old",
            "MailbellGoogleClientSecret": "old-secret"
        ])
        defer { try? FileManager.default.removeItem(at: plistURL) }

        let result = runInjector(
            arguments: [plistURL.path],
            environment: [
                OAuthConfig.clientIDKey: clientID
            ]
        )

        XCTAssertEqual(result.status, 0, result.stderr)
        let plist = try readStringPlist(plistURL)
        XCTAssertEqual(plist["MailbellGoogleClientID"], clientID)
        XCTAssertNil(plist["MailbellGoogleClientSecret"])
    }

    func testCheckPassesWithClientIDOnly() {
        let result = runInjector(
            arguments: ["--check"],
            environment: [
                OAuthConfig.clientIDKey: clientID
            ]
        )

        XCTAssertEqual(result.status, 0, result.stderr)
        XCTAssertFalse(result.stdout.contains(clientID))
    }

    func testReadsBundleIdentityFromDotEnv() throws {
        let plistURL = try makePlist([
            "CFBundleIdentifier": "com.example.old",
            "CFBundleName": "Old",
            "CFBundleDisplayName": "Old"
        ])
        let dotenvURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MailbellEnv.\(UUID().uuidString)")
        let dotenv = """
        \(OAuthConfig.clientIDKey)=\(clientID)
        \(OAuthConfig.clientSecretKey)=\(clientSecret)
        MAILBELL_BUNDLE_ID=dev.dotenv.mailbell
        """
        try dotenv.write(to: dotenvURL, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(at: plistURL)
            try? FileManager.default.removeItem(at: dotenvURL)
        }

        let result = runInjector(
            arguments: [plistURL.path],
            environment: [
                "MAILBELL_DOTENV_PATH": dotenvURL.path
            ]
        )

        XCTAssertEqual(result.status, 0, result.stderr)
        let plist = try readStringPlist(plistURL)
        XCTAssertEqual(plist["CFBundleIdentifier"], "dev.dotenv.mailbell")
        XCTAssertEqual(plist["CFBundleName"], "Mailbell")
        XCTAssertEqual(plist["CFBundleDisplayName"], "Mailbell")
    }

    func testCheckFailsWithoutCredentials() {
        let result = runInjector(arguments: ["--check"], environment: [:])

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.stderr.contains("set \(OAuthConfig.clientIDKey)"))
        XCTAssertFalse(result.stderr.contains("set \(OAuthConfig.clientIDKey) and \(OAuthConfig.clientSecretKey)"))
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func makePlist(_ values: [String: String]) throws -> URL {
        let plistURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MailbellInfo.\(UUID().uuidString).plist")
        let data = try PropertyListSerialization.data(fromPropertyList: values, format: .xml, options: 0)
        try data.write(to: plistURL)
        return plistURL
    }

    private func readStringPlist(_ url: URL) throws -> [String: String] {
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
    }

    private func runInjector(arguments: [String], environment: [String: String]) -> InjectorResult {
        let root = repositoryRoot()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [root.appendingPathComponent("Scripts/inject_bundle_config.sh").path] + arguments
        process.currentDirectoryURL = root

        var processEnvironment = ProcessInfo.processInfo.environment
        processEnvironment.removeValue(forKey: OAuthConfig.clientIDKey)
        processEnvironment.removeValue(forKey: OAuthConfig.clientSecretKey)
        processEnvironment.removeValue(forKey: "MAILBELL_BUNDLE_ID")
        processEnvironment.removeValue(forKey: "MAILBELL_CODE_SIGN_IDENTITY")
        processEnvironment.removeValue(forKey: "MAILBELL_NOTARY_KEYCHAIN_PROFILE")
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
