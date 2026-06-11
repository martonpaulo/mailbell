@testable import mailbell
import ServiceManagement
import XCTest

final class LoginItemTests: XCTestCase {
    func testMapsServiceManagementStatuses() {
        XCTAssertEqual(LoginItemStatus.from(.notRegistered), .disabled)
        XCTAssertEqual(LoginItemStatus.from(.enabled), .enabled)
        XCTAssertEqual(LoginItemStatus.from(.requiresApproval), .requiresApproval)
        XCTAssertEqual(LoginItemStatus.from(.notFound), .unavailable)
    }

    func testRequiresApprovalCopyPointsToSystemSettings() {
        let status = LoginItemStatus.requiresApproval

        XCTAssertEqual(status.title, "Requires approval")
        XCTAssertEqual(status.detail, "Approve Mailbell in System Settings > General > Login Items.")
    }
}
