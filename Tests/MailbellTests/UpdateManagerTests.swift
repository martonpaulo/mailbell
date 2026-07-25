@testable import mailbell
import XCTest

final class UpdateManagerTests: XCTestCase {
    func testBundleIsUpdatableOnlyWithBothHalvesOfTheSparkleContract() {
        let feed = "https://raw.githubusercontent.com/martonpaulo/mailbell/main/appcast.xml"
        let key = "6uivEfA8KeH2gsJHxX/ryov0kIjluroMuj0NyZ9OuLw="

        XCTAssertTrue(UpdateManager.isUpdatable(feedURL: feed, publicKey: key))
        XCTAssertFalse(UpdateManager.isUpdatable(feedURL: "", publicKey: key))
        XCTAssertFalse(UpdateManager.isUpdatable(feedURL: feed, publicKey: ""))
        XCTAssertFalse(UpdateManager.isUpdatable(feedURL: "   ", publicKey: "   "))
    }

    func testUpdateFeedMustBeHTTPS() {
        let key = "6uivEfA8KeH2gsJHxX/ryov0kIjluroMuj0NyZ9OuLw="

        XCTAssertFalse(UpdateManager.isUpdatable(feedURL: "http://example.com/appcast.xml", publicKey: key))
        XCTAssertFalse(UpdateManager.isUpdatable(feedURL: "file:///tmp/appcast.xml", publicKey: key))
        XCTAssertFalse(UpdateManager.isUpdatable(feedURL: "not a url", publicKey: key))
    }

    func testShippedInfoPlistDeclaresAWorkingUpdateFeed() throws {
        let plistURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Resources/Info.plist")
        let data = try Data(contentsOf: plistURL)
        let plist = try XCTUnwrap(
            try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )

        let feed = try XCTUnwrap(plist[UpdateManager.feedURLKey] as? String)
        let key = try XCTUnwrap(plist[UpdateManager.publicKeyKey] as? String)
        XCTAssertTrue(UpdateManager.isUpdatable(feedURL: feed, publicKey: key))
        XCTAssertEqual(plist["CFBundleIdentifier"] as? String, "com.perso.mailbell")
        XCTAssertEqual(plist["LSUIElement"] as? Bool, true)
    }

    func testVersionTextFallsBackToDevelopmentWithoutBundleMetadata() {
        XCTAssertEqual(AppVersion.text(bundle: Bundle(for: UpdateManagerTests.self)), "Development")
    }
}
