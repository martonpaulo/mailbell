import Foundation

// Nonisolated: moved inside MailMonitor run tasks.
nonisolated struct CheckpointStore {
    private let userDefaults: UserDefaults
    private let keys: StorageKeys.Checkpoint

    init(accountID: UUID, mailbox: String = "INBOX", userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        keys = StorageKeys.checkpoint(accountID: accountID, mailbox: mailbox)
    }

    var lastSeenUID: Int {
        get { userDefaults.integer(forKey: keys.lastSeenUID) }
        set { userDefaults.set(newValue, forKey: keys.lastSeenUID) }
    }

    var storedUIDValidity: Int {
        get { userDefaults.integer(forKey: keys.uidValidity) }
        set { userDefaults.set(newValue, forKey: keys.uidValidity) }
    }

    func reset() {
        userDefaults.removeObject(forKey: keys.uidValidity)
        userDefaults.removeObject(forKey: keys.lastSeenUID)
    }
}
