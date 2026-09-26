@testable import Mailbell
import XCTest

/// The capture mode must be invisible to ordinary launches, and the state a
/// capture depends on must come from the flag rather than from whatever the
/// developer last had open.
@MainActor
final class ScreenshotModeTests: XCTestCase {
    func testAnOrdinaryLaunchDoesNotEnterScreenshotMode() {
        XCTAssertFalse(ScreenshotMode.isEnabled(arguments: ["/Applications/Mailbell.app/Contents/MacOS/Mailbell"]))
        XCTAssertFalse(ScreenshotMode.isEnabled(arguments: []))
    }

    func testTheDocumentedArgumentEnablesIt() {
        XCTAssertTrue(ScreenshotMode.isEnabled(arguments: ["Mailbell", ScreenshotMode.launchArgument]))
    }

    func testThePaneDefaultsToTheFirstTabAndCanBeChosen() {
        XCTAssertEqual(ScreenshotMode.requestedPane(arguments: ["Mailbell", ScreenshotMode.launchArgument]), 0)
        XCTAssertEqual(
            ScreenshotMode.requestedPane(arguments: ["Mailbell", ScreenshotMode.paneArgument, "2"]),
            2
        )
        // A missing or unparseable value must not leave the pane to chance.
        XCTAssertEqual(ScreenshotMode.requestedPane(arguments: ["Mailbell", ScreenshotMode.paneArgument]), 0)
        XCTAssertEqual(
            ScreenshotMode.requestedPane(arguments: ["Mailbell", ScreenshotMode.paneArgument, "later"]),
            0
        )
    }

    func testTheAppearanceFollowsTheSystemUnlessPinned() {
        XCTAssertNil(ScreenshotMode.requestedAppearance(arguments: ["Mailbell", ScreenshotMode.launchArgument]))
        XCTAssertEqual(
            ScreenshotMode.requestedAppearance(arguments: ["Mailbell", ScreenshotMode.appearanceArgument, "light"]),
            .aqua
        )
        XCTAssertEqual(
            ScreenshotMode.requestedAppearance(arguments: ["Mailbell", ScreenshotMode.appearanceArgument, "dark"]),
            .darkAqua
        )
        // An unknown value must not pin anything by accident.
        XCTAssertNil(
            ScreenshotMode.requestedAppearance(arguments: ["Mailbell", ScreenshotMode.appearanceArgument, "sepia"])
        )
    }

    func testPinningClearsTheSavedFrameAndSelectsThePane() {
        let defaults = TestDefaults.make()
        defaults.set("stale frame", forKey: ScreenshotMode.windowFrameDefaultsKey)
        defaults.set(3, forKey: ScreenshotMode.selectedTabDefaultsKey)

        ScreenshotMode.pinEnvironment(defaults: defaults, pane: 1)

        XCTAssertNil(defaults.object(forKey: ScreenshotMode.windowFrameDefaultsKey))
        XCTAssertEqual(defaults.integer(forKey: ScreenshotMode.selectedTabDefaultsKey), 1)
    }

    /// scripts/lib/capture.sh reads these exact lines, and READY last.
    func testTheWindowIsReportedInTheCanonicalCaptureProtocol() {
        XCTAssertEqual(
            ScreenshotMode.protocolLines(scale: 2, windowNumber: 4321),
            ["SCALE 2.0", "WINDOW_ID 4321", "READY"]
        )
    }

    func testTheCaptureGoesThroughTheCanonicalLibrary() throws {
        let script = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("scripts/capture-screenshots.sh"),
            encoding: .utf8
        )

        XCTAssertTrue(script.contains(". scripts/lib/capture.sh"), "the capture protocol lives in the library")
        XCTAssertFalse(script.contains("--deep"), "only the outer bundle is re-signed")
    }
}
