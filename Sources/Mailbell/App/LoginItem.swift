import Foundation
import MailbellKit
import ServiceManagement

/// The launch-at-login state Settings shows: what macOS holds for the login
/// item, never the requested value and never a stored copy of it.
enum LoginItemStatus: Equatable {
    /// Registered and approved: Mailbell opens at login.
    case enabled
    /// Not registered.
    case disabled
    /// Registered, but macOS waits for approval in Login Items settings.
    case requiresApproval
    /// Cannot be registered from this binary (an unbundled executable).
    case unavailable

    /// The toggle is on whenever Mailbell is registered, including while
    /// approval is pending: turning it off is then what unregisters.
    var isOn: Bool {
        self == .enabled || self == .requiresApproval
    }

    /// `unavailable` is only reported while nothing is registered, so a
    /// registration can always be removed.
    var allowsChange: Bool {
        self != .unavailable
    }

    /// Only a pending approval has a native recovery destination.
    var offersLoginItemsSettings: Bool {
        self == .requiresApproval
    }

    /// On macOS 26 a bundled app that has never registered reads `notFound`, not
    /// `notRegistered`, so a packaged app shows Off and lets `register()` decide.
    /// Only an unbundled executable (`swift run`, the test host) cannot register.
    static func from(_ status: SMAppService.Status, isPackagedApp: Bool) -> LoginItemStatus {
        switch status {
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notRegistered, .notFound:
            return isPackagedApp ? .disabled : .unavailable
        @unknown default:
            return isPackagedApp ? .disabled : .unavailable
        }
    }
}

/// The outcome of a requested launch-at-login change: the status read back
/// after the call, and whether the request failed. A `register()` that throws
/// but leaves the item awaiting approval is not a failure.
struct LoginItemChange: Equatable {
    let status: LoginItemStatus
    let failed: Bool
}

/// Launch at login through `SMAppService.mainApp`.
///
/// Every result is read back from `SMAppService.Status`, never assumed from the
/// request. Reading the status has no side effect; only `set(_:)`, which runs
/// for the person's own change, registers or unregisters.
enum LoginItem {
    /// The ServiceManagement boundary. Tests substitute it so no automated run
    /// can touch this Mac's real login items.
    struct Service {
        var status: () -> SMAppService.Status
        var register: () throws -> Void
        var unregister: () throws -> Void
        var openLoginItemsSettings: () -> Void

        static var system: Service {
            Service(
                status: { SMAppService.mainApp.status },
                register: { try SMAppService.mainApp.register() },
                unregister: { try SMAppService.mainApp.unregister() },
                openLoginItemsSettings: { SMAppService.openSystemSettingsLoginItems() }
            )
        }
    }

    /// Reads the registration; never registers or unregisters anything.
    static var status: LoginItemStatus {
        // Captures present a fresh install's state, the way they pin every other fixture.
        if ScreenshotMode.isEnabled { return .disabled }
        return status(service: .system, isPackagedApp: AppIdentity.isPackagedApp)
    }

    /// Only the person's change calls this.
    @discardableResult
    static func set(_ enabled: Bool) -> LoginItemChange {
        set(enabled, service: .system, isPackagedApp: AppIdentity.isPackagedApp)
    }

    /// The native recovery destination for `requiresApproval`.
    static func openLoginItemsSettings() {
        Service.system.openLoginItemsSettings()
    }

    static func status(service: Service, isPackagedApp: Bool) -> LoginItemStatus {
        LoginItemStatus.from(service.status(), isPackagedApp: isPackagedApp)
    }

    /// Performs the change, then reads the status back: the result is what
    /// macOS holds. A thrown error matters only when the status read afterwards
    /// does not match the request.
    static func set(_ enabled: Bool, service: Service, isPackagedApp: Bool) -> LoginItemChange {
        let current = status(service: service, isPackagedApp: isPackagedApp)
        // Registering an unbundled executable would schedule the bare binary at
        // login, so it is refused before the no-op check can report success.
        if enabled && !isPackagedApp {
            return LoginItemChange(status: current, failed: true)
        }
        guard current.isOn != enabled else {
            return LoginItemChange(status: current, failed: false)
        }
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            // The status read below decides whether the request took effect.
            Log.app.error("Login item change threw: \(Log.detail(error), privacy: .private)")
        }
        let after = status(service: service, isPackagedApp: isPackagedApp)
        return LoginItemChange(status: after, failed: after.isOn != enabled)
    }
}
