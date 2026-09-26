import Foundation

/// Menu copy for the review queue: section titles, actions, counts and the
/// menu bar accessibility label.
public enum MenuCopy {
    public static let menuSectionTitle = String(localized: "Awaiting Review")
    public static let emptyMenuTitle = String(localized: "No messages")
    /// A bulk action closes the menu, so its outcome has to survive until the
    /// menu is opened again — otherwise a partial result is never seen.
    public static let lastActionPrefix = String(localized: "Last action: ")
    public static let signInErrorPrefix = String(localized: "Sign-in failed: ")
    public static let webmailErrorPrefix = String(localized: "Opening Gmail: ")
    public static let openActionTitle = String(localized: "Open")
    public static let markAsReadActionTitle = String(localized: "Mark as Read")
    public static let dismissActionTitle = String(localized: "Dismiss")
    public static let bulkActionsMenuTitle = String(localized: "All Messages")
    public static let markAllAsReadActionTitle = String(localized: "Mark All as Read")
    public static let markingAllAsReadActionTitle = String(localized: "Marking All as Read…")
    public static let dismissAllActionTitle = String(localized: "Dismiss All")

    /// Says what the queue holds without inventing a count of the mail still in
    /// Gmail, which Mailbell has no bounded way to know.
    public static func overflowNotice(hiddenConversations: Int) -> String? {
        guard hiddenConversations > 0 else { return nil }
        if hiddenConversations == 1 {
            return String(localized: "1 more conversation awaiting review. Open Gmail to see the rest.")
        }
        return String(
            localized: "\(hiddenConversations) more conversations awaiting review. Open Gmail to see the rest.")
    }

    /// Bulk actions reach every retained message, including the ones the menu
    /// has no room to show, so the count is stated before the action runs.
    public static func bulkActionScope(retainedMessages: Int) -> String {
        if retainedMessages == 1 {
            return String(localized: "Applies to 1 retained message")
        }
        return String(localized: "Applies to \(retainedMessages) retained messages")
    }

    public static func reviewCountText(_ count: Int) -> String {
        switch count {
        case 0:
            String(localized: "No messages")
        case 1:
            String(localized: "1 message")
        default:
            String(localized: "\(count) messages")
        }
    }

    public static func menuBarAccessibilityLabel(
        count: Int,
        showsCount: Bool = true,
        needsAttention: Bool = false,
        needsSignIn: Bool = false
    ) -> String {
        // Only say "sign in" when signing in is the remedy. A generic account
        // error is recovered with Reconnect, and naming the wrong action is
        // worse for someone who cannot see the icon than naming none.
        if needsSignIn {
            return String(localized: "Mailbell, sign in needed")
        }
        if needsAttention {
            return String(localized: "Mailbell, account needs attention")
        }
        guard showsCount, count > 0 else { return String(localized: "Mailbell") }
        if count == 1 {
            return String(localized: "Mailbell, 1 message awaiting review")
        }
        return String(localized: "Mailbell, \(count) messages awaiting review")
    }
}
