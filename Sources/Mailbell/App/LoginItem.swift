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
            "Disabled"
        case .enabled:
            "Enabled"
        case .requiresApproval:
            "Requires approval"
        case .unavailable:
            "Unavailable"
        }
    }

    var detail: String {
        switch self {
        case .disabled:
            "Mailbell will not start automatically."
        case .enabled:
            "Mailbell can start when you sign in."
        case .requiresApproval:
            "Approve Mailbell in System Settings > General > Login Items."
        case .unavailable:
            "Install and run Mailbell.app to manage start at login."
        }
    }

    static func from(_ status: SMAppService.Status) -> LoginItemStatus {
        switch status {
        case .notRegistered:
            return .disabled
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            return .unavailable
        @unknown default:
            return .unavailable
        }
    }
}

/// Start-at-login via SMAppService. Only works for a registered (bundled) app.
enum LoginItem {
    static var status: LoginItemStatus {
        LoginItemStatus.from(SMAppService.mainApp.status)
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
            Log.error("Failed to update login item: \(error.localizedDescription)")
        }
    }
}
