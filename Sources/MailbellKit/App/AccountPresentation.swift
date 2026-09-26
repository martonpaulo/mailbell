import Foundation

/// The single owner of the menu bar symbol. An account that needs the user to
/// act outranks unread mail, so the bell is replaced by an alert glyph instead
/// of silently looking idle while nothing is being monitored.
public enum MenuBarIcon {
    public static let idle = "bell"
    static let pending = "bell.fill"
    static let attention = "exclamationmark.triangle.fill"

    public static func systemImage(needsAttention: Bool, hasPendingItems: Bool) -> String {
        if needsAttention {
            return attention
        }
        return hasPendingItems ? pending : idle
    }
}

public enum PendingCopy {
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
    public static let reviewSectionTitle = String(localized: "Awaiting Review")

    /// Says what the queue holds without inventing a count of the mail still in
    /// Gmail, which Mailbell has no bounded way to know.
    public static func overflowNotice(hiddenConversations: Int) -> String? {
        guard hiddenConversations > 0 else { return nil }
        if hiddenConversations == 1 {
            return String(localized: "1 more conversation awaiting review. Open Gmail to see the rest.")
        }
        return String(localized: "\(hiddenConversations) more conversations awaiting review. Open Gmail to see the rest.")
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

public enum AccountRecoveryAction: Equatable, Sendable {
    case enable
    case reconnect
    case signInAgain

    public var title: String {
        switch self {
        case .enable:
            String(localized: "Enable Account")
        case .reconnect:
            String(localized: "Reconnect")
        case .signInAgain:
            String(localized: "Sign in Again")
        }
    }

    public var requiresAuthorizationSlot: Bool {
        self == .signInAgain
    }

    public static func needed(for state: AccountRuntimeState) -> AccountRecoveryAction? {
        guard state.account.isEnabled else { return .enable }
        switch state.status {
        case .signedOut, .error:
            return .reconnect
        case .reauthRequired:
            return .signInAgain
        case .connecting, .connected, .reconnecting:
            return nil
        }
    }
}

public enum AccountPresentation {
    public static func menuTitle(for state: AccountRuntimeState) -> String {
        String(localized: "\(statusText(for: state)) • \(state.account.email)")
    }

    public static func menuIconSystemName(for state: AccountRuntimeState) -> String {
        guard state.account.isEnabled else { return "pause.circle" }
        switch state.status {
        case .signedOut:
            return "circle"
        case .connecting, .reconnecting:
            return "arrow.clockwise.circle"
        case .connected:
            return "checkmark.circle.fill"
        case .reauthRequired, .error:
            return "exclamationmark.triangle.fill"
        }
    }

    public static func canRefresh(_ states: [AccountRuntimeState]) -> Bool {
        states.contains { $0.account.isEnabled }
    }

    public static func statusText(for state: AccountRuntimeState) -> String {
        guard state.account.isEnabled else { return String(localized: "Disabled") }
        switch state.status {
        case .signedOut:
            return String(localized: "Not connected")
        case .connecting:
            return String(localized: "Connecting")
        case .connected:
            return String(localized: "Connected")
        case .reconnecting:
            return String(localized: "Reconnecting")
        case .reauthRequired:
            return String(localized: "Sign in needed")
        case .error:
            return String(localized: "Needs attention")
        }
    }

    public static func detailText(for state: AccountRuntimeState, includeSpam: Bool = false) -> String {
        guard state.account.isEnabled else { return String(localized: "Gmail monitoring is paused for this account.") }
        switch state.status {
        case .signedOut:
            return String(localized: "Not connected.")
        case .connecting:
            return String(localized: "Connecting.")
        case .connected:
            return includeSpam
                ? String(localized: "Monitoring Inbox and Spam.")
                : String(localized: "Monitoring Inbox.")
        case .reconnecting:
            return String(localized: "Reconnecting.")
        case .reauthRequired:
            return String(localized: "Sign in again to resume monitoring.")
        case .error:
            return String(localized: "Check the error and reconnect.")
        }
    }
}
