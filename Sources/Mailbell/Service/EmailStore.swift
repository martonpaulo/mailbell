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
    private let userDefaults: UserDefaults
    private let recordsKey = "mailbell.emailStore.handledRecords.v1"
    private let maxRecordCount: Int
    private let now: () -> Date
    private var cachedRecords: [String: EmailStoreRecord]?

    init(
        userDefaults: UserDefaults = .standard,
        maxRecordCount: Int = 500,
        now: @escaping () -> Date = Date.init
    ) {
        self.userDefaults = userDefaults
        self.maxRecordCount = maxRecordCount
        self.now = now
    }

    func isHandled(_ id: String) -> Bool {
        records()[id] != nil
    }

    func suppressesUnreadSync(_ id: String) -> Bool {
        records()[id]?.disposition == .dismissed
    }

    func mark(_ id: String, disposition: EmailStoreDisposition) {
        var records = records()
        records[id] = EmailStoreRecord(id: id, disposition: disposition, updatedAt: now())
        save(pruned(records))
    }

    func removeRecords(accountID: UUID) {
        let prefix = EmailStoreIdentity.accountPrefix(accountID: accountID)
        let filtered = records().filter { id, _ in
            !id.hasPrefix(prefix)
        }
        save(filtered)
    }

    private func records() -> [String: EmailStoreRecord] {
        if let cachedRecords {
            return cachedRecords
        }
        guard let data = userDefaults.data(forKey: recordsKey),
              let decoded = try? JSONDecoder().decode([String: EmailStoreRecord].self, from: data)
        else {
            cachedRecords = [:]
            return [:]
        }
        cachedRecords = decoded
        return decoded
    }

    private func save(_ records: [String: EmailStoreRecord]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        userDefaults.set(data, forKey: recordsKey)
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

    func admit(header: MessageHeader, account: MailAccount) -> Bool {
        let id = EmailStoreIdentity.id(accountID: account.id, header: header)
        guard !persistence.isHandled(id) else {
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
    ) -> Bool {
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
            guard !persistence.suppressesUnreadSync(id) else { continue }
            nextItems[id] = makeItem(
                id: id,
                header: header,
                account: account,
                receivedAt: previousItems[id]?.receivedAt ?? now()
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

    func dismiss(id: String) {
        removeGroup(containing: id, disposition: .dismissed)
    }

    func markOpened(id: String) {
        removeGroup(containing: id, disposition: .opened)
    }

    func markRead(id: String) {
        removeGroup(containing: id, disposition: .markedRead)
    }

    func removeAccount(accountID: UUID) {
        let prefix = EmailStoreIdentity.accountPrefix(accountID: accountID)
        itemsByID = itemsByID.filter { id, _ in
            !id.hasPrefix(prefix)
        }
        persistence.removeRecords(accountID: accountID)
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
        if let leftUID = left.imapIdentity?.uid,
           let rightUID = right.imapIdentity?.uid,
           leftUID != rightUID {
            return leftUID < rightUID
        }
        return left.title.localizedCaseInsensitiveCompare(right.title) == .orderedAscending
    }

    private func removeGroup(containing id: String, disposition: EmailStoreDisposition) {
        guard let item = itemsByID[id] else {
            persistence.mark(id, disposition: disposition)
            itemsByID[id] = nil
            return
        }

        let groupID = item.groupID
        for groupedItem in itemsByID.values where groupedItem.groupID == groupID {
            persistence.mark(groupedItem.id, disposition: disposition)
        }
        itemsByID = itemsByID.filter { _, item in
            item.groupID != groupID
        }
    }

    private func makeItem(
        id: String,
        header: MessageHeader,
        account: MailAccount,
        receivedAt: Date? = nil
    ) -> EmailStoreItem {
        EmailStoreItem(
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
            receivedAt: receivedAt ?? now()
        )
    }
}
