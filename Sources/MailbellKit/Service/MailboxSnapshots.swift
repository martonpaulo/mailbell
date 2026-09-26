import Foundation

/// A mailbox one monitor watches: its role and the name the server gave it.
public struct MonitoredMailbox: Equatable, Sendable {
    public let role: MessageMailbox
    public let name: String

    public init(role: MessageMailbox, name: String) {
        self.role = role
        self.name = name
    }
}

/// The unread UIDs of one mailbox generation, as reconciliation saw them.
public struct MailboxUnreadSnapshot: Equatable, Sendable {
    public let mailbox: MessageMailbox
    public let mailboxName: String
    /// The generation the snapshot was taken under. Pending items captured
    /// under a different one are meaningless, not merely absent.
    public let uidValidity: Int
    public let unreadUIDs: Set<Int>

    public init(mailbox: MessageMailbox, mailboxName: String, uidValidity: Int, unreadUIDs: Set<Int>) {
        self.mailbox = mailbox
        self.mailboxName = mailboxName
        self.uidValidity = uidValidity
        self.unreadUIDs = unreadUIDs
    }
}
