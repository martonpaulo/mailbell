import Foundation

struct EmailStoreItem: Identifiable, Equatable {
    let id: String
    let accountID: UUID
    let accountEmail: String
    let mailbox: MessageMailbox
    let title: String
    let sender: String
    let time: String
    let webmailURL: URL
    let receivedAt: Date
}

enum EmailStoreIdentity {
    static func id(accountID: UUID, header: MessageHeader) -> String {
        let source = source(for: header)
        return "\(accountPrefix(accountID: accountID))\(source.kind).\(source.value)"
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
        itemsByID.values.sorted { left, right in
            if left.receivedAt != right.receivedAt {
                return left.receivedAt > right.receivedAt
            }
            return left.title.localizedCaseInsensitiveCompare(right.title) == .orderedAscending
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

    func replaceUnread(headers: [MessageHeader], account: MailAccount) -> Bool {
        let accountPrefix = EmailStoreIdentity.accountPrefix(accountID: account.id)
        let previousItems = itemsByID
        var nextItems = itemsByID.filter { id, _ in
            !id.hasPrefix(accountPrefix)
        }

        for header in headers {
            let id = EmailStoreIdentity.id(accountID: account.id, header: header)
            guard !persistence.isHandled(id) else { continue }
            nextItems[id] = previousItems[id] ?? makeItem(id: id, header: header, account: account)
        }

        guard nextItems != itemsByID else { return false }
        itemsByID = nextItems
        return true
    }

    func item(id: String) -> EmailStoreItem? {
        itemsByID[id]
    }

    func dismiss(id: String) {
        persistence.mark(id, disposition: .dismissed)
        itemsByID[id] = nil
    }

    func markOpened(id: String) {
        persistence.mark(id, disposition: .opened)
        itemsByID[id] = nil
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

    private func makeItem(id: String, header: MessageHeader, account: MailAccount) -> EmailStoreItem {
        EmailStoreItem(
            id: id,
            accountID: account.id,
            accountEmail: account.email,
            mailbox: header.mailbox,
            title: EmailHeaderFormatter.title(for: header),
            sender: EmailHeaderFormatter.senderDetail(from: header.from),
            time: EmailHeaderFormatter.timeText(for: header),
            webmailURL: MailProviderRegistry.provider(for: account.providerID)
                .webmailURL(for: header, account: account),
            receivedAt: now()
        )
    }
}
