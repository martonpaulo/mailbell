import Foundation

public struct AppSettingsStore {
    /// The single home for every configurable default. Views, tests, and
    /// Restore Defaults all read from here; no fallback value is duplicated.
    enum Defaults {
        static let showsMenuBarCount = true
        static let includeSpam = false
        static let playNotificationSounds = true
    }

    private let userDefaults: UserDefaults

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public var showsMenuBarCount: Bool {
        get {
            guard userDefaults.object(forKey: StorageKeys.showsMenuBarCount) != nil else {
                return Defaults.showsMenuBarCount
            }
            return userDefaults.bool(forKey: StorageKeys.showsMenuBarCount)
        }
        nonmutating set {
            userDefaults.set(newValue, forKey: StorageKeys.showsMenuBarCount)
        }
    }

    public var includeSpam: Bool {
        get {
            guard userDefaults.object(forKey: StorageKeys.includeSpam) != nil else {
                return Defaults.includeSpam
            }
            return userDefaults.bool(forKey: StorageKeys.includeSpam)
        }
        nonmutating set {
            userDefaults.set(newValue, forKey: StorageKeys.includeSpam)
        }
    }

    public var playNotificationSounds: Bool {
        get {
            guard userDefaults.object(forKey: StorageKeys.playNotificationSounds) != nil else {
                return Defaults.playNotificationSounds
            }
            return userDefaults.bool(forKey: StorageKeys.playNotificationSounds)
        }
        nonmutating set {
            userDefaults.set(newValue, forKey: StorageKeys.playNotificationSounds)
        }
    }

    /// Clears every configurable preference so the stored state falls back to
    /// `Defaults`. Never touches accounts, Keychain tokens, or notification
    /// permission.
    public func restoreDefaults() {
        for key in StorageKeys.settingsConfigurable {
            userDefaults.removeObject(forKey: key)
        }
    }
}
