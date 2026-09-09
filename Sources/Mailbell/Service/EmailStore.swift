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
    /// When Mailbell admitted the item. Orders members inside a group, so the
    /// first-admitted message stays the group's representative.
    let receivedAt: Date
    /// When the server received the message (IMAP INTERNALDATE). Orders the
    /// queue itself. Absent when the server did not answer a usable value.
    let serverReceivedAt: Date?
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
        // Last resort: a UID is only an identity inside one mailbox generation,
        // so both are part of the key. Gmail always supplies X-GM-MSGID, so
        // this branch is effectively unreachable for a Gmail account.
        return ("\(header.mailbox.rawValue).uid", "\(header.uidValidity).\(header.uid)")
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

/// The review queue is a recent, reconstructible window over Gmail, not a
/// mirror of it. Both limits are fixed product budgets rather than preferences:
/// there is no legitimate second answer for a user to choose, and Gmail remains
/// authoritative for everything outside the window.
enum PendingQueueBudget {
    /// Message records kept per account, shared by Inbox and Spam.
    static let retainedMessagesPerAccount = 500
    /// Conversation rows projected into the menu per account.
    static let visibleConversationsPerAccount = 50
}

enum EmailStoreDisposition: String, Codable, Equatable {
    case dismissed
    case markedRead
    case opened
}

/// The pending members handed to one server read request, fixed at capture time.
struct ReadSubmission: Equatable {
    let itemIDs: [String]
    let identities: [IMAPMessageIdentity]

    var isEmpty: Bool { identities.isEmpty }
}

/// A message plus where it lived when Mailbell handled it.
struct HandledMessage: Equatable {
    let id: String
    let identity: IMAPMessageIdentity?
}

@MainActor
final class EmailStore {
    /// Not private: EmailStore+Retention owns trimming this back to budget.
    var itemsByID: [String: EmailStoreItem] = [:]
    /// Not private: EmailStore+Actions records dispositions through it.
    let persistence: EmailStorePersistence
    private let now: () -> Date
    private var nextAdmissionOrder = 0

    init(
        persistence: EmailStorePersistence = EmailStorePersistence(),
        now: @escaping () -> Date = Date.init
    ) {
        self.persistence = persistence
        self.now = now
    }

    /// Retained message records for one account, which is what a bulk action
    /// reaches and what the overflow notice has to be honest about.
    func retainedMessageCount(accountID: UUID) -> Int {
        itemsByID.values.count { $0.accountID == accountID }
    }

    /// Conversations this account holds beyond the rows the menu can show.
    func hiddenConversationCount(accountID: UUID) -> Int {
        let total = Set(itemsByID.values.filter { $0.accountID == accountID }.map(\.groupID)).count
        return max(total - PendingQueueBudget.visibleConversationsPerAccount, 0)
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
        enforceRetentionBudget(accountID: account.id)
        return true
    }

    /// Every UID reconciliation should look past in this mailbox generation:
    /// what is already pending, plus what has already been handled. Without the
    /// second half, a newest window of dismissed messages is re-selected on
    /// every cycle and older unread mail never gets a turn.
    func uidsToSkip(
        accountID: UUID,
        mailbox: MessageMailbox,
        mailboxName: String,
        uidValidity: Int
    ) throws -> Set<Int> {
        let handled = try persistence.handledUIDs(
            accountID: accountID,
            mailboxName: mailboxName,
            uidValidity: uidValidity
        )
        return pendingUIDs(accountID: accountID, mailbox: mailbox, uidValidity: uidValidity)
            .union(handled)
    }

    /// UIDs already pending for this mailbox generation. Scoped by generation so
    /// a stale entry cannot suppress the fetch of a genuinely unknown message
    /// that now holds the same number.
    func pendingUIDs(accountID: UUID, mailbox: MessageMailbox, uidValidity: Int) -> Set<Int> {
        itemsByID.values.reduce(into: Set<Int>()) { result, item in
            guard item.accountID == accountID,
                  item.mailbox == mailbox,
                  let identity = item.imapIdentity,
                  identity.uidValidity == uidValidity
            else {
                return
            }
            result.insert(identity.uid)
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
            guard let identity = item.imapIdentity,
                  let snapshot = snapshotsByMailbox[item.mailbox]
            else {
                return true
            }
            // A pending item from an earlier generation points at a UID the
            // server may have handed to a different message. Drop it rather
            // than keep something no action could safely target. A snapshot
            // with no generation says nothing, so it clears nothing: the read
            // marker still refuses to act without a matching SELECT.
            guard snapshot.uidValidity == 0 || identity.uidValidity == snapshot.uidValidity else {
                return false
            }
            return snapshot.unreadUIDs.contains(identity.uid)
        }

        // A handled message Mailbell had no location for is recorded now, so
        // the next cycle can look past it instead of spending its whole budget
        // fetching the same discarded window again.
        try persistence.backfillLocation(fetchedHeaders.map { header in
            HandledMessage(
                id: EmailStoreIdentity.id(accountID: account.id, header: header),
                identity: header.imapIdentity
            )
        })

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
        enforceRetentionBudget(accountID: account.id)
        return true
    }

    func item(id: String) -> EmailStoreItem? {
        itemsByID[id]
    }

    func firstItemInGroup(containing id: String) -> EmailStoreItem? {
        guard let item = itemsByID[id] else { return nil }
        return firstItem(groupID: item.groupID)
    }

    /// The members of a group, captured before the server round trip.
    ///
    /// Marking as read awaits the network, and a reply can join the same thread
    /// while it is suspended. Finalizing "the group" on completion would then
    /// record a message the server was never asked about, so the submitted set
    /// is fixed here and carried through.
    func readSubmission(containing id: String) -> ReadSubmission {
        guard let item = itemsByID[id] else { return ReadSubmission(itemIDs: [], identities: []) }
        let members = itemsByID.values.filter { $0.groupID == item.groupID }
        return ReadSubmission(
            itemIDs: members.map(\.id),
            identities: members.compactMap(\.imapIdentity)
        )
    }

    /// Captures many groups in one pass. Calling `readSubmission` per group
    /// rescans the whole store each time, so a bulk run over N conversations
    /// costs N scans for no reason.
    func readSubmissions(containing ids: [String]) -> [ReadSubmission] {
        var membersByGroup: [String: [EmailStoreItem]] = [:]
        for item in itemsByID.values {
            membersByGroup[item.groupID, default: []].append(item)
        }
        return ids.map { id in
            guard let item = itemsByID[id], let members = membersByGroup[item.groupID] else {
                return ReadSubmission(itemIDs: [], identities: [])
            }
            return ReadSubmission(
                itemIDs: members.map(\.id),
                identities: members.compactMap(\.imapIdentity)
            )
        }
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

    func takePersistenceWarning() -> String? {
        persistence.takeRecoveryWarning()
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
            serverReceivedAt: header.serverReceivedAt,
            admissionOrder: resolvedAdmissionOrder
        )
    }
}
