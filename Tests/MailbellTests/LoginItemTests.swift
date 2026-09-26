import ServiceManagement
import XCTest

@testable import Mailbell

@MainActor
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

    func testTheToggleIsOnWhileRegisteredIncludingPendingApproval() {
        XCTAssertTrue(LoginItemStatus.enabled.isOn)
        XCTAssertTrue(LoginItemStatus.requiresApproval.isOn)
        XCTAssertFalse(LoginItemStatus.disabled.isOn)
        XCTAssertFalse(LoginItemStatus.unavailable.isOn)
        XCTAssertFalse(LoginItemStatus.unavailable.allowsChange)
        XCTAssertEqual(
            [LoginItemStatus.enabled, .disabled, .requiresApproval, .unavailable]
                .filter(\.offersLoginItemsSettings),
            [.requiresApproval]
        )
    }

    func testRequiresApprovalExplainsWhereToApprove() {
        let note = SettingsCopy.Startup.note(for: .requiresApproval, failed: false)

        XCTAssertEqual(
            note,
            "Mailbell is waiting for your approval in System Settings › General › Login Items & Extensions."
        )
        XCTAssertNil(SettingsCopy.Startup.note(for: .enabled, failed: false))
        XCTAssertNil(SettingsCopy.Startup.note(for: .disabled, failed: false))
        XCTAssertEqual(SettingsCopy.Startup.note(for: .disabled, failed: true), SettingsCopy.Startup.changeFailed)
    }

    // MARK: - Changes

    func testEnablingRegistersOnceAndReadsTheStatusBack() {
        let service = FakeLoginItemService(status: .notRegistered)
        service.statusAfterRegister = .enabled

        let change = LoginItem.set(true, service: service.service, isPackagedApp: true)

        XCTAssertEqual(change, LoginItemChange(status: .enabled, failed: false))
        XCTAssertEqual(service.calls, ["register"])
    }

    func testARegistrationAwaitingApprovalIsNotAFailure() {
        let service = FakeLoginItemService(status: .notFound)
        service.statusAfterRegister = .requiresApproval
        service.registerError = FakeLoginItemService.Failure()

        let change = LoginItem.set(true, service: service.service, isPackagedApp: true)

        XCTAssertEqual(change, LoginItemChange(status: .requiresApproval, failed: false))
    }

    func testARegistrationThatDidNotTakeEffectFails() {
        let service = FakeLoginItemService(status: .notRegistered)
        service.registerError = FakeLoginItemService.Failure()

        let change = LoginItem.set(true, service: service.service, isPackagedApp: true)

        XCTAssertEqual(change, LoginItemChange(status: .disabled, failed: true))
        XCTAssertEqual(service.calls, ["register"])
    }

    func testDisablingUnregisters() {
        let service = FakeLoginItemService(status: .enabled)
        service.statusAfterUnregister = .notRegistered

        let change = LoginItem.set(false, service: service.service, isPackagedApp: true)

        XCTAssertEqual(change, LoginItemChange(status: .disabled, failed: false))
        XCTAssertEqual(service.calls, ["unregister"])
    }

    func testAnUnbundledExecutableNeverRegisters() {
        let service = FakeLoginItemService(status: .notFound)

        let change = LoginItem.set(true, service: service.service, isPackagedApp: false)

        XCTAssertEqual(change, LoginItemChange(status: .unavailable, failed: true))
        XCTAssertEqual(service.calls, [])
    }

    func testEnablingWhileApprovalIsPendingChangesNothing() {
        let service = FakeLoginItemService(status: .requiresApproval)

        let change = LoginItem.set(true, service: service.service, isPackagedApp: true)

        XCTAssertEqual(change, LoginItemChange(status: .requiresApproval, failed: false))
        XCTAssertEqual(service.calls, [])
    }

    func testReadingTheStatusNeverChangesTheRegistration() {
        let service = FakeLoginItemService(status: .requiresApproval)

        XCTAssertEqual(LoginItem.status(service: service.service, isPackagedApp: true), .requiresApproval)
        XCTAssertEqual(service.calls, [])
    }
}

/// Stands in for `SMAppService.mainApp`, so no test touches this Mac's login items.
@MainActor
final class FakeLoginItemService {
    struct Failure: Error {}

    var status: SMAppService.Status
    var statusAfterRegister: SMAppService.Status?
    var statusAfterUnregister: SMAppService.Status?
    var registerError: Error?
    private(set) var calls: [String] = []

    init(status: SMAppService.Status) {
        self.status = status
    }

    var service: LoginItem.Service {
        LoginItem.Service(
            status: { self.status },
            register: {
                self.calls.append("register")
                if let next = self.statusAfterRegister { self.status = next }
                if let error = self.registerError { throw error }
            },
            unregister: {
                self.calls.append("unregister")
                if let next = self.statusAfterUnregister { self.status = next }
            },
            openLoginItemsSettings: {
                self.calls.append("openLoginItemsSettings")
            }
        )
    }
}
