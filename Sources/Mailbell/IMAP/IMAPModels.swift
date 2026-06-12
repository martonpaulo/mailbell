import Foundation

/// A minimal message header set, just enough to render a notification.
struct MessageHeader: Identifiable, Equatable {
    let uid: Int
    let from: String
    let subject: String
    let date: String
    let gmThreadId: String?
    let gmMessageId: String?
    let messageId: String?

    init(
        uid: Int,
        from: String,
        subject: String,
        date: String,
        gmThreadId: String?,
        gmMessageId: String? = nil,
        messageId: String? = nil
    ) {
        self.uid = uid
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
}

/// Result of selecting a mailbox; the checkpoint for gap-fill on reconnect.
struct MailboxState {
    var uidValidity: Int
    var uidNext: Int
    var exists: Int
}
