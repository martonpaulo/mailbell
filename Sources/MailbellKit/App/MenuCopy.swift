import Foundation

/// Every string the menu bar dropdown shows, plus the menu bar accessibility
/// label. The menu counts in one unit, the conversation; messages appear only
/// where an action's reach is stated (Decided on #69).
public enum MenuCopy {
    // MARK: - Counting unit

    /// The label beside a review count outside the menu, such as a Settings row.
    public static let menuSectionTitle = String(localized: "To review")

    /// A conversation count on its own, for a row that already says "To review".
    public static func reviewCountText(_ count: Int) -> String {
        switch count {
        case 0:
            String(localized: "No conversations")
        case 1:
            String(localized: "1 conversation")
        default:
            String(localized: "\(count) conversations")
        }
    }

    /// The one phrase for what waits in the queue: the queue header, each
    /// account's submenu and the menu bar accessibility label all read it.
    public static func toReview(_ count: Int) -> String {
        switch count {
        case 0:
            String(localized: "Nothing to review")
        case 1:
            String(localized: "1 conversation to review")
        default:
            String(localized: "\(count) conversations to review")
        }
    }

    // MARK: - Queue

    public static let checkForNewMail = String(localized: "Check for New Mail")

    /// Says what the queue holds without inventing a count of the mail still in
    /// Gmail, which Mailbell has no bounded way to know.
    public static func overflowNotice(hiddenConversations: Int) -> String? {
        guard hiddenConversations > 0 else { return nil }
        if hiddenConversations == 1 {
            return String(localized: "1 more conversation not shown. Open Gmail to see it.")
        }
        return String(localized: "\(hiddenConversations) more conversations not shown. Open Gmail to see them.")
    }

    // MARK: - Rows

    public static let openInGmail = String(localized: "Open in Gmail")
    public static let markAsRead = String(localized: "Mark as Read in Gmail")
    public static let dismiss = String(localized: "Dismiss (Keep Unread in Gmail)")
    public static let yesterday = String(localized: "Yesterday")

    /// A row's title when its conversation holds more than one retained message.
    public static func sender(_ name: String, messages: Int) -> String {
        String(
            localized: "\(name) (\(messages))",
            comment: "A sender followed by the number of messages in the conversation.")
    }

    public static func sender(_ name: String, address: String) -> String {
        String(localized: "\(name) <\(address)>", comment: "A sender's name followed by their email address.")
    }

    public static func rowSubtitle(subject: String, time: String) -> String {
        String(localized: "\(subject) · \(time)", comment: "A menu row's subtitle: the subject, then when it arrived.")
    }

    public static func recipient(_ account: String, time: String) -> String {
        String(localized: "To \(account) · \(time)", comment: "The account a message was sent to, then when.")
    }

    public static func markAsReadFailed(subject: String) -> String {
        String(localized: "Couldn't mark “\(subject)” as read in Gmail. Try again.")
    }

    // MARK: - Bulk actions

    public static let bulkMenuTitle = String(localized: "All Conversations")
    public static let markAllAsRead = String(localized: "Mark All as Read in Gmail")
    /// The same command while a confirmation follows it, as the HIG asks.
    public static let markAllAsReadConfirming = String(localized: "Mark All as Read in Gmail…")
    public static let markingAllAsRead = String(localized: "Marking as Read in Gmail…")
    public static let dismissAll = String(localized: "Dismiss All (Keep Unread in Gmail)")

    /// Bulk actions reach every retained message, including the ones the menu
    /// has no room to show, so the reach is stated before the action runs.
    public static func bulkScope(messages: Int, conversations: Int) -> String {
        switch (messages, conversations) {
        case (1, _):
            String(localized: "Includes 1 message in 1 conversation.")
        case (_, 1):
            String(localized: "Includes \(messages) messages in 1 conversation.")
        default:
            String(localized: "Includes \(messages) messages in \(conversations) conversations.")
        }
    }

    public enum Confirmation {
        public static let confirm = String(localized: "Mark as Read")
        public static let cancel = String(localized: "Cancel")

        public static func title(messages: Int) -> String {
            messages == 1
                ? String(localized: "Mark 1 message as read in Gmail?")
                : String(localized: "Mark \(messages) messages as read in Gmail?")
        }

        public static func message(hiddenMessages: Int) -> String {
            hiddenMessages == 1
                ? String(
                    localized: "1 of them isn't shown in the menu. Gmail shows them as read on all your devices.")
                : String(
                    localized:
                        "\(hiddenMessages) of them aren't shown in the menu. Gmail shows them as read on all your devices."
                )
        }
    }

    /// A bulk action closes the menu, so its outcome stays until the menu is
    /// opened again; otherwise a partial result is never seen.
    public enum BulkResult {
        public static let nothingPending = String(localized: "Nothing to review.")
        public static let markFailed = String(localized: "Couldn't mark messages as read in Gmail. Try again.")

        public static func marked(messages: Int) -> String {
            messages == 1
                ? String(localized: "Marked 1 message as read in Gmail.")
                : String(localized: "Marked \(messages) messages as read in Gmail.")
        }

        public static func partiallyMarked(marked: Int, failed: Int) -> String {
            String(localized: "\(Self.marked(messages: marked)) \(failed) couldn't be updated. Try again.")
        }

        public static func dismissed(messages: Int) -> String {
            messages == 1
                ? String(localized: "Dismissed 1 message. It stays unread in Gmail.")
                : String(localized: "Dismissed \(messages) messages. They stay unread in Gmail.")
        }
    }

    // MARK: - Problems

    /// The menu's problem row and the sign-in notification's title.
    public static func needsSignIn(_ address: String) -> String {
        String(localized: "\(address) needs sign-in", comment: "The placeholder is a Gmail address.")
    }

    public static let needsSignInDetail = String(
        localized: "Mailbell can't watch this account until you sign in again.")

    public static func cantConnect(_ address: String) -> String {
        String(localized: "Can't connect to \(address)", comment: "The placeholder is a Gmail address.")
    }

    public static let notificationsOff = String(localized: "Notifications are off")
    public static let notificationsOffDetail = String(
        localized: "In System Settings, go to Notifications, then choose Mailbell.")
    /// Names what it opens: no documented public API opens the Notifications
    /// pane itself (docs/interface.md, Decided on #31).
    public static let openSystemSettings = String(localized: "Open System Settings")

    // MARK: - Accounts and app commands

    public static let noAccount = String(localized: "No Gmail account")
    /// Sign-in follows in the browser, so the command asks for more input.
    public static let addAccount = String(localized: "Add Gmail Account…")
    public static let signingIn = String(localized: "Signing In…")
    public static let accountsMenuTitle = String(localized: "Accounts")
    public static let openGmail = String(localized: "Open Gmail")
    public static let checkForUpdates = String(localized: "Check for Updates…")
    public static let settings = String(localized: "Settings…")
    public static let quit = String(localized: "Quit Mailbell")

    // MARK: - Menu bar accessibility label

    public static func menuBarAccessibilityLabel(
        count: Int,
        showsCount: Bool = true,
        needsAttention: Bool = false,
        needsSignIn: Bool = false
    ) -> String {
        // Only say "sign-in" when signing in is the remedy. A generic account
        // error is recovered with Reconnect, and naming the wrong action is
        // worse for someone who cannot see the icon than naming none.
        if needsSignIn {
            return String(localized: "Mailbell, sign-in needed")
        }
        if needsAttention {
            return String(localized: "Mailbell, can't connect")
        }
        guard showsCount, count > 0 else { return String(localized: "Mailbell") }
        return String(localized: "Mailbell, \(toReview(count))", comment: "The placeholder is a count to review.")
    }
}
