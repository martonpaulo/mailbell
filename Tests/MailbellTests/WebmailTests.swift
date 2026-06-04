@testable import mailbell
import Foundation
import XCTest

final class WebmailTests: XCTestCase {
    func testLegacyMailAccountJSONDecodesWithoutWebmailPreference() throws {
        let json = """
        {
          "id": "A1B2C3D4-E5F6-7890-ABCD-EF1234567890",
          "providerID": "gmail",
          "email": "legacy@example.com",
          "isEnabled": true,
          "createdAt": 0
        }
        """
        let jsonData = Data(json.utf8)

        let account = try JSONDecoder().decode(MailAccount.self, from: jsonData)
        XCTAssertNil(account.webmailOpenPreference)
    }

    func testMailAccountRoundTripsWebmailPreference() throws {
        let account = MailAccount(
            providerID: .gmail,
            email: "user@example.com",
            webmailOpenPreference: WebmailOpenPreference(
                browser: .application(
                    bundleIdentifier: BrowserRegistry.chromeBundleID,
                    appPath: "/Applications/Google Chrome.app"
                ),
                chromeProfileDirectory: "Profile 2"
            )
        )

        let data = try JSONEncoder().encode(account)
        let decoded = try JSONDecoder().decode(MailAccount.self, from: data)

        XCTAssertEqual(decoded.webmailOpenPreference, account.webmailOpenPreference)
    }

    func testBrowserRegistryPreferenceForSystemDefaultIsNil() {
        XCTAssertNil(BrowserRegistry.preference(for: .systemDefault, chromeProfileDirectory: nil))
    }

    func testBrowserRegistryPreferenceClearsChromeProfileForNonChrome() {
        let safari = BrowserCandidate(
            id: "com.apple.Safari",
            displayName: "Safari",
            bundleIdentifier: "com.apple.Safari",
            appURL: URL(fileURLWithPath: "/Applications/Safari.app"),
            supportsChromeProfiles: false
        )

        let preference = BrowserRegistry.preference(for: safari, chromeProfileDirectory: "Profile 1")
        XCTAssertEqual(
            preference?.browser,
            .application(bundleIdentifier: "com.apple.Safari", appPath: "/Applications/Safari.app")
        )
        XCTAssertNil(preference?.chromeProfileDirectory)
    }

    func testBrowserOptionsIncludesSavedBrowserWhenDiscoveryMissesIt() {
        let preference = WebmailOpenPreference(
            browser: .application(
                bundleIdentifier: BrowserRegistry.chromeBundleID,
                appPath: "/Applications/Google Chrome.app"
            ),
            chromeProfileDirectory: nil
        )

        let options = BrowserRegistry.browserOptions(matching: preference, browsers: [.systemDefault])

        XCTAssertEqual(options.map(\.id), [BrowserCandidate.systemDefaultID, BrowserRegistry.chromeBundleID])
    }

    func testChromeProfileOptionsIncludeMissingSavedProfile() {
        let profiles = [
            ChromeProfileCandidate(directory: "Default", displayName: "Personal", userName: "personal@example.com")
        ]

        let options = AccountWebmailSettingsView.chromeProfileOptions(
            savedDirectory: "Profile 9",
            profiles: profiles
        )

        XCTAssertEqual(options.map(\.directory), ["", "Default", "Profile 9"])
        XCTAssertEqual(options.last?.label, "Profile 9 (missing)")
    }

    func testChromeProfileOptionsDoNotDuplicateExistingSavedProfile() {
        let profiles = [
            ChromeProfileCandidate(directory: "Default", displayName: "Personal", userName: "personal@example.com")
        ]

        let options = AccountWebmailSettingsView.chromeProfileOptions(
            savedDirectory: "Default",
            profiles: profiles
        )

        XCTAssertEqual(options.map(\.directory), ["", "Default"])
    }

    func testChromeProfileStoreParsesLocalStateFixture() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("WebmailTests.\(UUID().uuidString)", isDirectory: true)
        let chromeDir = home.appendingPathComponent("Library/Application Support/Google/Chrome", isDirectory: true)
        try FileManager.default.createDirectory(at: chromeDir, withIntermediateDirectories: true)

        let localState = """
        {
          "profile": {
            "info_cache": {
              "Default": {
                "name": "Personal",
                "user_name": "personal@example.com"
              },
              "Profile 2": {
                "name": "Work",
                "user_name": "work@example.com"
              },
              "Guest Profile": {
                "name": "Guest Profile"
              }
            }
          }
        }
        """
        try localState.write(to: chromeDir.appendingPathComponent("Local State"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(
            at: chromeDir.appendingPathComponent("Default", isDirectory: true),
            withIntermediateDirectories: true
        )

        let profiles = ChromeProfileStore.loadProfiles(homeDirectory: home)
        XCTAssertEqual(profiles.map(\.directory), ["Default", "Profile 2"])
        XCTAssertEqual(profiles.first?.displayName, "Personal")
        XCTAssertEqual(profiles.first?.userName, "personal@example.com")
        XCTAssertTrue(ChromeProfileStore.profileExists(directory: "Default", homeDirectory: home))
        XCTAssertFalse(ChromeProfileStore.profileExists(directory: "Profile 9", homeDirectory: home))
    }
}
