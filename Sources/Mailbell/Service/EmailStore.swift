import Foundation

struct EmailStoreItem: Identifiable, Equatable {
    let id: String
    let groupID: String
    let accountID: UUID
    let accountEmail: String
    let mailbox: MessageMailbox
    let imapIdentity: IMAPMessageIdentity?
    let title: String
    let sender: String
    let time: String
    let bodyPreview: String?
    let webmailURL: URL
    let receivedAt: Date
    let admissionOrder: Int

    var canMarkAsRead: Bool {
        imapIdentity != nil
    }

    var bodyPreviewLines: [String] {
        bodyPreview?
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init) ?? []
    }
}

enum EmailStoreIdentity {
    static func id(accountID: UUID, header: MessageHeader) -> String {
        let source = source(for: header)
        return "\(accountPrefix(accountID: accountID))\(source.kind).\(source.value)"
    }

    static func groupID(accountID: UUID, header: MessageHeader) -> String {
        if let value = normalized(header.gmThreadId) {
            return "\(accountPrefix(accountID: accountID))gmailThread.\(value)"
        }
        return id(accountID: accountID, header: header)
    }

    static func accountPrefix(accountID: UUID) -> String {
        "mailbell.account.\(accountID.uuidString).email."
    }

    private static func source(for header: MessageHeader) -> (kind: String, value: String) {
        if let value = normalized(header.gmMessageId) {
            return ("gmailMessage", value)
        }
        if let value = normalized(header.gmThreadId) {
            return ("gmailThread", value)
        }
        if let value = normalizedMessageID(header.messageId) {
            return ("rfcMessage", value)
        }
        return ("\(header.mailbox.rawValue).uid", String(header.uid))
    }

    private static func normalized(_ value: String?) -> String? {
        let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let normalized, !normalized.isEmpty else { return nil }
        return normalized
    }

    private static func normalizedMessageID(_ value: String?) -> String? {
        guard var normalized = normalized(value) else { return nil }
        if normalized.hasPrefix("<"), normalized.hasSuffix(">"), normalized.count > 2 {
            normalized = String(normalized.dropFirst().dropLast())
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return normalized.isEmpty ? nil : normalized
    }
}

enum EmailStoreDisposition: String, Codable, Equatable {
    case dismissed
    case markedRead
    case opened
}

private struct EmailStoreRecord: Codable, Equatable {
    var id: String
    var disposition: EmailStoreDisposition
    var updatedAt: Date
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

    func mark(_ id: String, disposition: EmailStoreDisposition) throws {
        try mark([id], disposition: disposition)
    }

    func mark(_ ids: [String], disposition: EmailStoreDisposition) throws {
        guard !ids.isEmpty else { return }
        var records = try records()
        let updatedAt = now()
        for id in ids {
            records[id] = EmailStoreRecord(id: id, disposition: disposition, updatedAt: updatedAt)
        }
        try save(pruned(records))
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

@MainActor
final class EmailStore {
    private var itemsByID: [String: EmailStoreItem] = [:]
    private let persistence: EmailStorePersistence
    private let now: () -> Date
    private var nextAdmissionOrder = 0

    init(
        persistence: EmailStorePersistence = EmailStorePersistence(),
        now: @escaping () -> Date = Date.init
    ) {
        self.persistence = persistence
        self.now = now
    }

    var items: [EmailStoreItem] {
        groupedItems().sorted { left, right in
            if left.receivedAt != right.receivedAt {
                return left.receivedAt > right.receivedAt
            }
            return left.title.localizedCaseInsensitiveCompare(right.title) == .orderedAscending
        }
    }

    var pendingCountsByAccountID: [UUID: Int] {
        items.reduce(into: [:]) { counts, item in
            counts[item.accountID, default: 0] += 1
        }
    }

    var hasItems: Bool {
        !itemsByID.isEmpty
    }

    func admit(header: MessageHeader, account: MailAccount) throws -> Bool {
        let id = EmailStoreIdentity.id(accountID: account.id, header: header)
        guard try !persistence.isHandled(id) else {
            itemsByID[id] = nil
            return false
        }
        guard itemsByID[id] == nil else {
            return false
        }

        itemsByID[id] = makeItem(id: id, header: header, account: account)
        return true
    }

    func pendingUIDs(accountID: UUID, mailbox: MessageMailbox) -> Set<Int> {
        itemsByID.values.reduce(into: Set<Int>()) { result, item in
            guard item.accountID == accountID,
                  item.mailbox == mailbox,
                  let uid = item.imapIdentity?.uid
            else {
                return
            }
            result.insert(uid)
        }
    }

    func reconcileUnread(
        snapshots: [MailboxUnreadSnapshot],
        fetchedHeaders: [MessageHeader],
        account: MailAccount
    ) throws -> Bool {
        let previousItems = itemsByID
        let snapshotsByMailbox = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.mailbox, $0) })
        let monitoredMailboxes = Set(snapshotsByMailbox.keys)

        var nextItems = itemsByID.filter { _, item in
            guard item.accountID == account.id,
                  monitoredMailboxes.contains(item.mailbox)
            else {
                return true
            }
            guard let uid = item.imapIdentity?.uid else {
                return true
            }
            return snapshotsByMailbox[item.mailbox]?.unreadUIDs.contains(uid) == true
        }

        for header in fetchedHeaders {
            guard let snapshot = snapshotsByMailbox[header.mailbox],
                  snapshot.unreadUIDs.contains(header.uid)
            else {
                continue
            }
            let id = EmailStoreIdentity.id(accountID: account.id, header: header)
            guard try !persistence.suppressesUnreadSync(id) else { continue }
            nextItems[id] = makeItem(
                id: id,
                header: header,
                account: account,
                receivedAt: previousItems[id]?.receivedAt ?? now(),
                admissionOrder: previousItems[id]?.admissionOrder
            )
        }

        guard nextItems != itemsByID else { return false }
        itemsByID = nextItems
        return true
    }

    func item(id: String) -> EmailStoreItem? {
        itemsByID[id]
    }

    func firstItemInGroup(containing id: String) -> EmailStoreItem? {
        guard let item = itemsByID[id] else { return nil }
        return firstItem(groupID: item.groupID)
    }

    func imapIdentitiesInGroup(containing id: String) -> [IMAPMessageIdentity] {
        guard let item = itemsByID[id] else { return [] }
        return itemsByID.values
            .filter { $0.groupID == item.groupID }
            .compactMap(\.imapIdentity)
    }

    func dismiss(id: String) throws {
        try removeGroup(containing: id, disposition: .dismissed)
    }

    func markOpened(id: String) throws {
        try removeGroup(containing: id, disposition: .opened)
    }

    func markRead(id: String) throws {
        try removeGroup(containing: id, disposition: .markedRead)
    }

    func removeAccountRecords(accountID: UUID) throws {
        try persistence.removeRecords(accountID: accountID)
    }

    func removeAccountItems(accountID: UUID) {
        let prefix = EmailStoreIdentity.accountPrefix(accountID: accountID)
        itemsByID = itemsByID.filter { id, _ in
            !id.hasPrefix(prefix)
        }
    }

    func removeSpamItems() -> Bool {
        let previousItems = itemsByID
        itemsByID = itemsByID.filter { _, item in
            item.mailbox != .spam
        }
        return previousItems != itemsByID
    }

    private func groupedItems() -> [EmailStoreItem] {
        var firstItemsByGroupID: [String: EmailStoreItem] = [:]
        for item in itemsByID.values {
            guard let existing = firstItemsByGroupID[item.groupID] else {
                firstItemsByGroupID[item.groupID] = item
                continue
            }
            if isEarlierInGroup(item, than: existing) {
                firstItemsByGroupID[item.groupID] = item
            }
        }
        return Array(firstItemsByGroupID.values)
    }

    private func firstItem(groupID: String) -> EmailStoreItem? {
        itemsByID.values
            .filter { $0.groupID == groupID }
            .min { left, right in
                isEarlierInGroup(left, than: right)
            }
    }

    private func isEarlierInGroup(_ left: EmailStoreItem, than right: EmailStoreItem) -> Bool {
        if left.receivedAt != right.receivedAt {
            return left.receivedAt < right.receivedAt
        }
        if left.admissionOrder != right.admissionOrder {
            return left.admissionOrder < right.admissionOrder
        }
        if let leftUID = left.imapIdentity?.uid,
           let rightUID = right.imapIdentity?.uid,
           leftUID != rightUID {
            return leftUID < rightUID
        }
        return left.title.localizedCaseInsensitiveCompare(right.title) == .orderedAscending
    }

    func takePersistenceWarning() -> String? {
        persistence.takeRecoveryWarning()
    }

    private func removeGroup(containing id: String, disposition: EmailStoreDisposition) throws {
        guard let item = itemsByID[id] else {
            try persistence.mark(id, disposition: disposition)
            itemsByID[id] = nil
            return
        }

        let groupID = item.groupID
        let groupedIDs = itemsByID.values
            .filter { $0.groupID == groupID }
            .map(\.id)
        try persistence.mark(groupedIDs, disposition: disposition)
        itemsByID = itemsByID.filter { _, item in
            item.groupID != groupID
        }
    }

    private func makeItem(
        id: String,
        header: MessageHeader,
        account: MailAccount,
        receivedAt: Date? = nil,
        admissionOrder: Int? = nil
    ) -> EmailStoreItem {
        let resolvedAdmissionOrder: Int
        if let admissionOrder {
            resolvedAdmissionOrder = admissionOrder
        } else {
            resolvedAdmissionOrder = nextAdmissionOrder
            nextAdmissionOrder += 1
        }

        return EmailStoreItem(
            id: id,
            groupID: EmailStoreIdentity.groupID(accountID: account.id, header: header),
            accountID: account.id,
            accountEmail: account.email,
            mailbox: header.mailbox,
            imapIdentity: header.imapIdentity,
            title: EmailHeaderFormatter.title(for: header),
            sender: EmailHeaderFormatter.senderDetail(from: header.from),
            time: EmailHeaderFormatter.timeText(for: header),
            bodyPreview: header.bodyPreview,
            webmailURL: MailProviderRegistry.provider(for: account.providerID)
                .webmailURL(for: header, account: account),
            receivedAt: receivedAt ?? now(),
            admissionOrder: resolvedAdmissionOrder
        )
    }
}
