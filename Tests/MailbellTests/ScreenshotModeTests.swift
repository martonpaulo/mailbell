@testable import mailbell
import XCTest

/// The capture mode must be invisible to ordinary launches, and the state a
/// capture depends on must come from the flag rather than from whatever the
/// developer last had open.
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

    func testPinningClearsTheSavedFrameAndSelectsThePane() {
        let suiteName = "mailbell.tests.screenshot.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("stale frame", forKey: ScreenshotMode.windowFrameDefaultsKey)
        defaults.set(3, forKey: ScreenshotMode.selectedTabDefaultsKey)

        ScreenshotMode.pinEnvironment(defaults: defaults, pane: 1)

        XCTAssertNil(defaults.object(forKey: ScreenshotMode.windowFrameDefaultsKey))
        XCTAssertEqual(defaults.integer(forKey: ScreenshotMode.selectedTabDefaultsKey), 1)
    }

    func testTheReportedWindowIDRoundTrips() {
        let line = ScreenshotMode.windowIDLine(4321)

        XCTAssertEqual(ScreenshotMode.parseWindowID(line), 4321)
        XCTAssertNil(ScreenshotMode.parseWindowID(ScreenshotMode.readyMarker))
        XCTAssertNil(ScreenshotMode.parseWindowID("MAILBELL_SCREENSHOT_WINDOW_ID=not-a-number"))
    }

    func testTheCaptureScriptNeverStripsTheShadow() throws {
        let script = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Scripts/capture_screenshots.sh"),
            encoding: .utf8
        )

        XCTAssertTrue(script.contains("screencapture -x -l"), "must capture the real on-screen window by id")
        XCTAssertFalse(script.contains("screencapture -o"), "-o removes the window shadow")
        XCTAssertTrue(script.contains("-lossless"), "published pixels must be identical to the capture")
    }
}
