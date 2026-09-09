import Foundation

private struct EmailStoreRecord: Codable, Equatable {
    var id: String
    var disposition: EmailStoreDisposition
    var updatedAt: Date
    /// Where the message sat when it was handled. Optional because records
    /// written before this existed decode without it; they are backfilled the
    /// next time reconciliation sees the message, so the history heals itself
    /// in one cycle rather than needing a migration.
    var mailboxName: String?
    var uidValidity: Int?
    var uid: Int?
}

final class EmailStorePersistence {
    enum PersistenceError: Error, LocalizedError {
        case decodingFailed(String)
        case encodingFailed(String)
        case saveFailed(String)

        var errorDescription: String? {
            switch self {
            case let .decodingFailed(detail):
                "Could not read handled-message history: \(detail)"
            case let .encodingFailed(detail):
                "Could not encode handled-message history: \(detail)"
            case let .saveFailed(detail):
                "Could not save handled-message history: \(detail)"
            }
        }
    }

    static let recoveryWarning =
        "Handled-message history was reset because saved state was unreadable. Some items may reappear."

    private let userDefaults: UserDefaults
    static let recordsKey = "mailbell.emailStore.handledRecords.v1"
    static let corruptBackupKey = "mailbell.emailStore.handledRecords.corruptBackup.v1"
    private let maxRecordCount: Int
    private let now: () -> Date
    private let saveData: (_ data: Data, _ key: String) throws -> Void
    private var cachedRecords: [String: EmailStoreRecord]?
    private var pendingRecoveryWarning: String?

    init(
        userDefaults: UserDefaults = .standard,
        maxRecordCount: Int = 500,
        now: @escaping () -> Date = Date.init,
        saveData: ((_ data: Data, _ key: String) throws -> Void)? = nil
    ) {
        self.userDefaults = userDefaults
        self.maxRecordCount = maxRecordCount
        self.now = now
        self.saveData = saveData ?? { [userDefaults] data, key in
            userDefaults.set(data, forKey: key)
        }
    }

    func isHandled(_ id: String) throws -> Bool {
        try records()[id] != nil
    }

    func suppressesUnreadSync(_ id: String) throws -> Bool {
        try records()[id]?.disposition == .dismissed
    }

    func mark(_ handled: HandledMessage, disposition: EmailStoreDisposition) throws {
        try mark([handled], disposition: disposition)
    }

    func mark(_ handled: [HandledMessage], disposition: EmailStoreDisposition) throws {
        guard !handled.isEmpty else { return }
        var records = try records()
        let updatedAt = now()
        for message in handled {
            records[message.id] = EmailStoreRecord(
                id: message.id,
                disposition: disposition,
                updatedAt: updatedAt,
                mailboxName: message.identity?.mailboxName,
                uidValidity: message.identity?.uidValidity,
                uid: message.identity?.uid
            )
        }
        try save(pruned(records))
    }

    /// Teaches an existing record where its message lives. Reconciliation calls
    /// this when it meets a handled message it had no location for, so the next
    /// cycle can skip it without downloading it again.
    func backfillLocation(_ handled: [HandledMessage]) throws {
        var records = try records()
        var didChange = false
        for message in handled {
            guard let identity = message.identity,
                  var record = records[message.id],
                  record.uid == nil
            else {
                continue
            }
            record.mailboxName = identity.mailboxName
            record.uidValidity = identity.uidValidity
            record.uid = identity.uid
            records[message.id] = record
            didChange = true
        }
        guard didChange else { return }
        try save(records)
    }

    /// UIDs this account has already handled in one mailbox generation, so
    /// reconciliation can look past them instead of spending its whole budget
    /// re-fetching the same discarded window on every cycle.
    func handledUIDs(accountID: UUID, mailboxName: String, uidValidity: Int) throws -> Set<Int> {
        let prefix = EmailStoreIdentity.accountPrefix(accountID: accountID)
        return try records().values.reduce(into: Set<Int>()) { result, record in
            guard record.id.hasPrefix(prefix),
                  record.mailboxName == mailboxName,
                  record.uidValidity == uidValidity,
                  let uid = record.uid
            else {
                return
            }
            result.insert(uid)
        }
    }

    func removeRecords(accountID: UUID) throws {
        let prefix = EmailStoreIdentity.accountPrefix(accountID: accountID)
        let records = try records()
        let filtered = records.filter { id, _ in
            !id.hasPrefix(prefix)
        }
        guard filtered != records else { return }
        try save(filtered)
    }

    func takeRecoveryWarning() -> String? {
        let warning = pendingRecoveryWarning
        pendingRecoveryWarning = nil
        return warning
    }

    private func records() throws -> [String: EmailStoreRecord] {
        if let cachedRecords {
            return cachedRecords
        }
        guard let data = userDefaults.data(forKey: Self.recordsKey) else {
            cachedRecords = [:]
            return [:]
        }
        do {
            let decoded = try JSONDecoder().decode([String: EmailStoreRecord].self, from: data)
            cachedRecords = decoded
            return decoded
        } catch {
            try recoverCorruptRecords(data)
            pendingRecoveryWarning = Self.recoveryWarning
            cachedRecords = [:]
            return [:]
        }
    }

    private func recoverCorruptRecords(_ data: Data) throws {
        let emptyRecords = [String: EmailStoreRecord]()
        do {
            try saveData(data, Self.corruptBackupKey)
            let emptyData = try JSONEncoder().encode(emptyRecords)
            try saveData(emptyData, Self.recordsKey)
        } catch let error as PersistenceError {
            throw error
        } catch let error as EncodingError {
            throw PersistenceError.encodingFailed(error.localizedDescription)
        } catch {
            throw PersistenceError.saveFailed(error.localizedDescription)
        }
    }

    private func save(_ records: [String: EmailStoreRecord]) throws {
        let data: Data
        do {
            data = try JSONEncoder().encode(records)
        } catch {
            throw PersistenceError.encodingFailed(error.localizedDescription)
        }

        do {
            try saveData(data, Self.recordsKey)
        } catch let error as PersistenceError {
            throw error
        } catch {
            throw PersistenceError.saveFailed(error.localizedDescription)
        }
        cachedRecords = records
    }

    private func pruned(_ records: [String: EmailStoreRecord]) -> [String: EmailStoreRecord] {
        guard records.count > maxRecordCount else { return records }

        let retained = records.values
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(maxRecordCount)

        return Dictionary(uniqueKeysWithValues: retained.map { ($0.id, $0) })
    }
}
