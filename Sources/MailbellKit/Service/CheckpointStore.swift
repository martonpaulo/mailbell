import Foundation

public struct CheckpointStore {
    private let userDefaults: UserDefaults
    private let keys: StorageKeys.Checkpoint

    public init(accountID: UUID, mailbox: String = "INBOX", userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        keys = StorageKeys.checkpoint(accountID: accountID, mailbox: mailbox)
    }

    public var lastSeenUID: Int {
        get { userDefaults.integer(forKey: keys.lastSeenUID) }
        set { userDefaults.set(newValue, forKey: keys.lastSeenUID) }
    }

    public var storedUIDValidity: Int {
        get { userDefaults.integer(forKey: keys.uidValidity) }
        set { userDefaults.set(newValue, forKey: keys.uidValidity) }
    }

    public func reset() {
        userDefaults.removeObject(forKey: keys.uidValidity)
        userDefaults.removeObject(forKey: keys.lastSeenUID)
    }
}
