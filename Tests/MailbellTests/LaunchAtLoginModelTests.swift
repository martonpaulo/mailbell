@testable import Mailbell
import XCTest

@MainActor
final class LaunchAtLoginModelTests: XCTestCase {
    private var reported: LoginItemStatus = .disabled
    private var requests: [Bool] = []
    private var nextChange = LoginItemChange(status: .enabled, failed: false)
    private var opened = 0

    private func makeModel() -> LaunchAtLoginModel {
        LaunchAtLoginModel(
            readStatus: { self.reported },
            change: { isOn in
                self.requests.append(isOn)
                return self.nextChange
            },
            openLoginItemsSettings: { self.opened += 1 }
        )
    }

    func testRefreshOnlyReadsTheStatus() {
        let model = makeModel()
        reported = .requiresApproval

        model.refresh()
        model.refresh()

        XCTAssertEqual(model.status, .requiresApproval)
        XCTAssertTrue(model.status.isOn)
        XCTAssertEqual(requests, [])
    }

    func testRequestStoresTheStatusReadBack() {
        let model = makeModel()
        nextChange = LoginItemChange(status: .requiresApproval, failed: false)

        model.request(true)

        XCTAssertEqual(requests, [true])
        XCTAssertEqual(model.status, .requiresApproval)
        XCTAssertFalse(model.failed)
    }

    func testAFailedRequestKeepsItsNoteUntilTheStatusChanges() {
        let model = makeModel()
        nextChange = LoginItemChange(status: .disabled, failed: true)

        model.request(true)
        model.refresh()
        XCTAssertTrue(model.failed)

        reported = .enabled
        model.refresh()

        XCTAssertEqual(model.status, .enabled)
        XCTAssertFalse(model.failed)
        XCTAssertEqual(requests, [true])
    }

    func testOpeningLoginItemsSettingsUsesTheInjectedAction() {
        let model = makeModel()

        model.openLoginItemsSettings()

        XCTAssertEqual(opened, 1)
    }
}
