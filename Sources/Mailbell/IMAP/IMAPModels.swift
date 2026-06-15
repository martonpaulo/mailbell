import Foundation

enum MessageMailbox: String, Equatable {
    case inbox
    case spam
}

/// A minimal message header set, just enough to render a notification.
struct MessageHeader: Identifiable, Equatable {
    let uid: Int
    let mailbox: MessageMailbox
    let from: String
    let subject: String
    let date: String
    let gmThreadId: String?
    let gmMessageId: String?
    let messageId: String?

    init(
        uid: Int,
        mailbox: MessageMailbox = .inbox,
        from: String,
        subject: String,
        date: String,
        gmThreadId: String?,
        gmMessageId: String? = nil,
        messageId: String? = nil
    ) {
        self.uid = uid
        self.mailbox = mailbox
        self.from = from
        self.subject = subject
        self.date = date
        self.gmThreadId = gmThreadId
        self.gmMessageId = gmMessageId
        self.messageId = messageId
    }

    var id: Int {
        uid
    }

    func assigningMailbox(_ mailbox: MessageMailbox) -> MessageHeader {
        MessageHeader(
            uid: uid,
            mailbox: mailbox,
            from: from,
            subject: subject,
            date: date,
            gmThreadId: gmThreadId,
            gmMessageId: gmMessageId,
            messageId: messageId
        )
    }
}

/// Result of selecting a mailbox; the checkpoint for gap-fill on reconnect.
struct MailboxState {
    var uidValidity: Int
    var uidNext: Int
    var exists: Int
}
