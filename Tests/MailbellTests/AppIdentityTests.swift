@testable import mailbell
import XCTest

final class AppIdentityTests: XCTestCase {
    func testPackagedAppDetectionAcceptsAppBundleURL() {
        XCTAssertTrue(
            AppIdentity.isPackagedApp(
                bundleURL: URL(fileURLWithPath: "/Applications/Mailbell.app"),
                executableURL: nil,
                arguments: []
            )
        )
    }

    func testPackagedAppDetectionAcceptsExecutableInsideAppBundle() {
        XCTAssertTrue(
            AppIdentity.isPackagedApp(
                bundleURL: URL(fileURLWithPath: "/Applications/Mailbell.app/Contents/MacOS"),
                executableURL: URL(fileURLWithPath: "/Applications/Mailbell.app/Contents/MacOS/Mailbell"),
                arguments: []
            )
        )
    }

    func testPackagedAppDetectionRejectsUnbundledExecutable() {
        XCTAssertFalse(
            AppIdentity.isPackagedApp(
                bundleURL: URL(fileURLWithPath: "/Users/perso/Projects/mailbell/.build/release"),
                executableURL: URL(fileURLWithPath: "/Users/perso/Projects/mailbell/.build/release/mailbell"),
                arguments: []
            )
        )
    }
}
