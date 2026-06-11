import Foundation

enum AppPreferenceKeys {
    static let showMenuBarIcon = "mailbell.showMenuBarIcon"
}

enum AppPreferences {
    static let defaultShowMenuBarIcon = true

    static func showMenuBarIcon(userDefaults: UserDefaults = .standard) -> Bool {
        guard userDefaults.object(forKey: AppPreferenceKeys.showMenuBarIcon) != nil else {
            return defaultShowMenuBarIcon
        }
        return userDefaults.bool(forKey: AppPreferenceKeys.showMenuBarIcon)
    }

    static func setShowMenuBarIcon(_ value: Bool, userDefaults: UserDefaults = .standard) {
        userDefaults.set(value, forKey: AppPreferenceKeys.showMenuBarIcon)
    }
}

enum SettingsSectionOrder {
    static let titles = ["Notifications", "Startup", "Accounts"]
}
