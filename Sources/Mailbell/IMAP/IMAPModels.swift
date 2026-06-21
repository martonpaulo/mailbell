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

struct IMAPMessageIdentity: Equatable, Hashable {
    let uid: Int
    let mailboxName: String

    init?(uid: Int, mailboxName: String) {
        let normalizedMailboxName = mailboxName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard uid > 0, !normalizedMailboxName.isEmpty else { return nil }
        self.uid = uid
        self.mailboxName = normalizedMailboxName
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
        bodyPreview: String? = nil
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
    }

    var id: Int {
        uid
    }

    var imapIdentity: IMAPMessageIdentity? {
        IMAPMessageIdentity(uid: uid, mailboxName: mailboxName)
    }

    func assigningMailbox(_ mailbox: MessageMailbox, name: String? = nil) -> MessageHeader {
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
            bodyPreview: bodyPreview
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
            bodyPreview: bodyPreview
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
