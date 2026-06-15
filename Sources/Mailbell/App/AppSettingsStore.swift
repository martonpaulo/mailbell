import Foundation

struct AppSettingsStore {
    private enum Key {
        static let showPendingCount = "mailbell.settings.showPendingCount.v1"
        static let includeSpam = "mailbell.settings.includeSpam.v1"
    }

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    var showPendingCount: Bool {
        get {
            if userDefaults.object(forKey: Key.showPendingCount) == nil {
                return true
            }
            return userDefaults.bool(forKey: Key.showPendingCount)
        }
        nonmutating set {
            userDefaults.set(newValue, forKey: Key.showPendingCount)
        }
    }

    var includeSpam: Bool {
        get {
            userDefaults.bool(forKey: Key.includeSpam)
        }
        nonmutating set {
            userDefaults.set(newValue, forKey: Key.includeSpam)
        }
    }
}
