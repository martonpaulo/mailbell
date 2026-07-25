import Foundation

struct AppSettingsStore {
    /// The single home for every configurable default. Views, tests, and
    /// Restore Defaults all read from here; no fallback value is duplicated.
    enum Defaults {
        static let showPendingCount = true
        static let includeSpam = false
    }

    enum Key {
        static let showPendingCount = "mailbell.settings.showPendingCount.v1"
        static let includeSpam = "mailbell.settings.includeSpam.v1"

        /// Every preference Restore Defaults resets. Identity, tokens, account
        /// metadata, IMAP checkpoints, and handled-message history are user
        /// data, not preferences, and are deliberately absent.
        static let configurable = [showPendingCount, includeSpam]
    }

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    var showPendingCount: Bool {
        get {
            guard userDefaults.object(forKey: Key.showPendingCount) != nil else {
                return Defaults.showPendingCount
            }
            return userDefaults.bool(forKey: Key.showPendingCount)
        }
        nonmutating set {
            userDefaults.set(newValue, forKey: Key.showPendingCount)
        }
    }

    var includeSpam: Bool {
        get {
            guard userDefaults.object(forKey: Key.includeSpam) != nil else {
                return Defaults.includeSpam
            }
            return userDefaults.bool(forKey: Key.includeSpam)
        }
        nonmutating set {
            userDefaults.set(newValue, forKey: Key.includeSpam)
        }
    }

    /// Clears every configurable preference so the stored state falls back to
    /// `Defaults`. Never touches accounts, Keychain tokens, or notification
    /// permission.
    func restoreDefaults() {
        for key in Key.configurable {
            userDefaults.removeObject(forKey: key)
        }
    }
}
