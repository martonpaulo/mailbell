import Foundation
import ServiceManagement

/// Start-at-login via SMAppService. Only works for a registered (bundled) app.
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
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
