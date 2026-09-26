@testable import Mailbell
import ServiceManagement
import XCTest

final class LoginItemTests: XCTestCase {
    func testPackagedAppMapsNeverRegisteredStatusesToDisabled() {
        XCTAssertEqual(LoginItemStatus.from(.notRegistered, isPackagedApp: true), .disabled)
        XCTAssertEqual(LoginItemStatus.from(.notFound, isPackagedApp: true), .disabled)
        XCTAssertEqual(LoginItemStatus.from(.enabled, isPackagedApp: true), .enabled)
        XCTAssertEqual(LoginItemStatus.from(.requiresApproval, isPackagedApp: true), .requiresApproval)
    }

    func testUnpackagedExecutableCannotUseLoginItems() {
        XCTAssertEqual(LoginItemStatus.from(.notRegistered, isPackagedApp: false), .unavailable)
        XCTAssertEqual(LoginItemStatus.from(.notFound, isPackagedApp: false), .unavailable)
        XCTAssertEqual(LoginItemStatus.from(.enabled, isPackagedApp: false), .enabled)
        XCTAssertEqual(LoginItemStatus.from(.requiresApproval, isPackagedApp: false), .requiresApproval)
    }

    func testRequiresApprovalCopyPointsToSystemSettings() {
        let status = LoginItemStatus.requiresApproval

        XCTAssertEqual(status.title, "Requires approval")
        XCTAssertEqual(status.detail, "Approve Mailbell in System Settings > General > Login Items.")
    }
}
