import Foundation

enum MessageMailbox: String, Equatable {
    case inbox
    case spam

    var defaultIMAPName: String {
        switch self {
        case .inbox:
            "INBOX"
        case .spam:
            "SPAM"
        }
    }
}

/// RFC 3501 section 2.3.1.1 identifies a message by mailbox name, UIDVALIDITY
/// and UID together. A UID alone is not an identity: once the generation
/// changes the server may reuse the number for a different message, and an
/// action prepared under the old generation would mutate the wrong mail.
struct IMAPMessageIdentity: Equatable, Hashable {
    let uid: Int
    let mailboxName: String
    let uidValidity: Int

    init?(uid: Int, mailboxName: String, uidValidity: Int) {
        let normalizedMailboxName = mailboxName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard uid > 0, uidValidity > 0, !normalizedMailboxName.isEmpty else { return nil }
        self.uid = uid
        self.mailboxName = normalizedMailboxName
        self.uidValidity = uidValidity
    }
}

/// A minimal message header set, just enough to render a notification.
struct MessageHeader: Identifiable, Equatable {
    let uid: Int
    let mailbox: MessageMailbox
    let mailboxName: String
    let from: String
    let subject: String
    let date: String
    let gmThreadId: String?
    let gmMessageId: String?
    let messageId: String?
    let bodyPreview: String?
    /// The mailbox generation this header was fetched under. Zero means the
    /// fetch path did not record one, which makes the message unactionable
    /// rather than actionable against the wrong generation.
    let uidValidity: Int
    /// Server receipt time (IMAP INTERNALDATE), the timestamp Gmail orders the
    /// inbox by. Kept separate from `date`, which is the sender's own Date
    /// header and can be wrong or absent.
    let serverReceivedAt: Date?

    init(
        uid: Int,
        mailbox: MessageMailbox = .inbox,
        mailboxName: String? = nil,
        from: String,
        subject: String,
        date: String,
        gmThreadId: String?,
        gmMessageId: String? = nil,
        messageId: String? = nil,
        bodyPreview: String? = nil,
        uidValidity: Int = 0,
        serverReceivedAt: Date? = nil
    ) {
        self.uid = uid
        self.mailbox = mailbox
        self.mailboxName = Self.normalizedMailboxName(mailboxName, mailbox: mailbox)
        self.from = from
        self.subject = subject
        self.date = date
        self.gmThreadId = gmThreadId
        self.gmMessageId = gmMessageId
        self.messageId = messageId
        self.bodyPreview = bodyPreview
        self.uidValidity = uidValidity
        self.serverReceivedAt = serverReceivedAt
    }

    var id: Int {
        uid
    }

    var imapIdentity: IMAPMessageIdentity? {
        IMAPMessageIdentity(uid: uid, mailboxName: mailboxName, uidValidity: uidValidity)
    }

    func assigningMailbox(
        _ mailbox: MessageMailbox,
        name: String? = nil,
        uidValidity: Int? = nil
    ) -> MessageHeader {
        MessageHeader(
            uid: uid,
            mailbox: mailbox,
            mailboxName: name,
            from: from,
            subject: subject,
            date: date,
            gmThreadId: gmThreadId,
            gmMessageId: gmMessageId,
            messageId: messageId,
            bodyPreview: bodyPreview,
            uidValidity: uidValidity ?? self.uidValidity,
            serverReceivedAt: serverReceivedAt
        )
    }

    func assigningBodyPreview(_ bodyPreview: String?) -> MessageHeader {
        MessageHeader(
            uid: uid,
            mailbox: mailbox,
            mailboxName: mailboxName,
            from: from,
            subject: subject,
            date: date,
            gmThreadId: gmThreadId,
            gmMessageId: gmMessageId,
            messageId: messageId,
            bodyPreview: bodyPreview,
            uidValidity: uidValidity,
            serverReceivedAt: serverReceivedAt
        )
    }

    private static func normalizedMailboxName(_ name: String?, mailbox: MessageMailbox) -> String {
        let normalized = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let normalized, !normalized.isEmpty else { return mailbox.defaultIMAPName }
        return normalized
    }
}

/// Result of selecting a mailbox; the checkpoint for gap-fill on reconnect.
struct MailboxState {
    var uidValidity: Int
    var uidNext: Int
    var exists: Int
}
