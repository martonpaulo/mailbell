import CoreGraphics
import XCTest

@testable import Mailbell

/// Sparkle's update window fits its release notes (#75).
final class UpdateAlertSizingTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1720, height: 1409)
    /// 565 x 390 with a 195 pt notes area.
    private let window = CGRect(x: 565, y: 600, width: 565, height: 390)

    func testAShortWindowGrowsDownToShowAllTheNotes() {
        let fitted = UpdateAlertSizing.fittedFrame(
            window: window, notesViewHeight: 195, contentHeight: 481,
            minimumHeight: 300, visibleScreen: screen)

        // chrome 195 + notes 481, top edge kept
        XCTAssertEqual(fitted, CGRect(x: 565, y: 314, width: 565, height: 676))
    }

    func testATallWindowShrinksToTheNotes() {
        let tall = CGRect(x: 565, y: 406, width: 565, height: 951)
        let fitted = UpdateAlertSizing.fittedFrame(
            window: tall, notesViewHeight: 760, contentHeight: 300.4,
            minimumHeight: 300, visibleScreen: screen)

        // chrome 191 + notes rounded up to 301, top edge kept
        XCTAssertEqual(fitted, CGRect(x: 565, y: 865, width: 565, height: 492))
    }

    func testTheWindowNeverGetsShorterThanItsMinimum() {
        let fitted = UpdateAlertSizing.fittedFrame(
            window: window, notesViewHeight: 195, contentHeight: 40,
            minimumHeight: 300, visibleScreen: screen)

        XCTAssertEqual(fitted, CGRect(x: 565, y: 690, width: 565, height: 300))
    }

    func testLongNotesStopAtTheScreenHeight() {
        let fitted = UpdateAlertSizing.fittedFrame(
            window: window, notesViewHeight: 195, contentHeight: 5000,
            minimumHeight: 300, visibleScreen: screen)

        XCTAssertEqual(fitted, CGRect(x: 565, y: 0, width: 565, height: 1409))
    }

    func testGrowingPastTheBottomMovesTheWindowUp() {
        let low = CGRect(x: 565, y: 20, width: 565, height: 390)
        let fitted = UpdateAlertSizing.fittedFrame(
            window: low, notesViewHeight: 195, contentHeight: 600,
            minimumHeight: 300, visibleScreen: screen)

        // chrome 195 + notes 600, raised to the bottom of the visible screen
        XCTAssertEqual(fitted, CGRect(x: 565, y: 0, width: 565, height: 795))
    }

    func testNothingMeasuredLeavesTheWindowAlone() {
        let fitted = UpdateAlertSizing.fittedFrame(
            window: window, notesViewHeight: 195, contentHeight: 0,
            minimumHeight: 300, visibleScreen: screen)

        XCTAssertEqual(fitted, window)
    }
}
