import Foundation

/// A minimal message header set, just enough to render a notification.
struct MessageHeader: Identifiable, Equatable {
    let uid: Int
    let from: String
    let subject: String
    let date: String
    let gmThreadId: String?

    var id: Int { uid }

    /// Best-effort Gmail Web deep link to the thread (see docs/design.md).
    /// Gmail's X-GM-THRID is decimal; the web client uses the hex form.
    func gmailURL(account: String) -> URL {
        guard let thrid = gmThreadId, let value = UInt64(thrid) else {
            return URL(string: "https://mail.google.com/mail/u/0/#inbox")!
        }
        let hex = String(value, radix: 16)
        return URL(string: "https://mail.google.com/mail/u/0/#inbox/\(hex)")!
    }
}

/// Result of selecting a mailbox; the checkpoint for gap-fill on reconnect.
struct MailboxState {
    var uidValidity: Int
    var uidNext: Int
    var exists: Int
}
