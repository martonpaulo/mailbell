import Foundation
import ServiceManagement

enum LoginItemStatus: Equatable {
    case disabled
    case enabled
    case requiresApproval
    case unavailable

    var title: String {
        switch self {
        case .disabled:
            String(localized: "Disabled")
        case .enabled:
            String(localized: "Enabled")
        case .requiresApproval:
            String(localized: "Requires approval")
        case .unavailable:
            String(localized: "Unavailable")
        }
    }

    var detail: String {
        switch self {
        case .disabled:
            String(localized: "Mailbell will not start automatically.")
        case .enabled:
            String(localized: "Mailbell can start when you sign in.")
        case .requiresApproval:
            String(localized: "Approve Mailbell in System Settings > General > Login Items.")
        case .unavailable:
            String(localized: "Install and run Mailbell.app to manage start at login.")
        }
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

/// Start-at-login via SMAppService. Only works for a registered (bundled) app.
enum LoginItem {
    static var status: LoginItemStatus {
        // Captures present a fresh install's state, the way they pin every other fixture.
        if ScreenshotMode.isEnabled { return .disabled }
        return LoginItemStatus.from(SMAppService.mainApp.status, isPackagedApp: AppIdentity.isPackagedApp)
    }

    static var isEnabled: Bool {
        status == .enabled
    }

    static func set(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Log.app.error("Failed to update login item: \(Log.detail(error), privacy: .public)")
        }
    }
}
