import Foundation

struct CheckpointStore {
    private static let legacyUIDValidityKey = "mailbell.uidValidity"
    private static let legacyLastUIDKey = "mailbell.lastSeenUID"

    private let userDefaults: UserDefaults
    private let uidValidityKey: String
    private let lastUIDKey: String

    init(accountID: UUID, mailbox: String = "INBOX", userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        let namespace = "mailbell.account.\(accountID.uuidString).mailbox.\(mailbox)"
        uidValidityKey = "\(namespace).uidValidity"
        lastUIDKey = "\(namespace).lastSeenUID"
    }

    var lastSeenUID: Int {
        get { userDefaults.integer(forKey: lastUIDKey) }
        set { userDefaults.set(newValue, forKey: lastUIDKey) }
    }

    var storedUIDValidity: Int {
        get { userDefaults.integer(forKey: uidValidityKey) }
        set { userDefaults.set(newValue, forKey: uidValidityKey) }
    }

    func reset() {
        userDefaults.removeObject(forKey: uidValidityKey)
        userDefaults.removeObject(forKey: lastUIDKey)
    }

    static func migrateLegacyCheckpoint(to accountID: UUID, userDefaults: UserDefaults = .standard) {
        var store = CheckpointStore(accountID: accountID, userDefaults: userDefaults)
        guard store.storedUIDValidity == 0, store.lastSeenUID == 0 else { return }

        let legacyUIDValidity = userDefaults.integer(forKey: legacyUIDValidityKey)
        let legacyLastUID = userDefaults.integer(forKey: legacyLastUIDKey)
        if legacyUIDValidity != 0 {
            store.storedUIDValidity = legacyUIDValidity
        }
        if legacyLastUID != 0 {
            store.lastSeenUID = legacyLastUID
        }
    }
}
