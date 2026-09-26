import Foundation

/// The single owner of the menu bar symbol. An account that needs the user to
/// act outranks unread mail, so the bell is replaced by an alert glyph instead
/// of silently looking idle while nothing is being monitored.
enum MenuBarIcon {
    static let idle = "bell"
    static let pending = "bell.fill"
    static let attention = "exclamationmark.triangle.fill"

    static func systemImage(needsAttention: Bool, hasPendingItems: Bool) -> String {
        if needsAttention {
            return attention
        }
        return hasPendingItems ? pending : idle
    }
}

enum PendingCopy {
    static let menuSectionTitle = String(localized: "Awaiting Review")
    static let emptyMenuTitle = String(localized: "No messages")
    /// A bulk action closes the menu, so its outcome has to survive until the
    /// menu is opened again — otherwise a partial result is never seen.
    static let lastActionPrefix = String(localized: "Last action: ")
    static let signInErrorPrefix = String(localized: "Sign-in failed: ")
    static let webmailErrorPrefix = String(localized: "Opening Gmail: ")
    static let openActionTitle = String(localized: "Open")
    static let markAsReadActionTitle = String(localized: "Mark as Read")
    static let dismissActionTitle = String(localized: "Dismiss")
    static let bulkActionsMenuTitle = String(localized: "All Messages")
    static let markAllAsReadActionTitle = String(localized: "Mark All as Read")
    static let markingAllAsReadActionTitle = String(localized: "Marking All as Read…")
    static let dismissAllActionTitle = String(localized: "Dismiss All")
    static let reviewSectionTitle = String(localized: "Awaiting Review")

    /// Says what the queue holds without inventing a count of the mail still in
    /// Gmail, which Mailbell has no bounded way to know.
    static func overflowNotice(hiddenConversations: Int) -> String? {
        guard hiddenConversations > 0 else { return nil }
        if hiddenConversations == 1 {
            return String(localized: "1 more conversation awaiting review. Open Gmail to see the rest.")
        }
        return String(localized: "\(hiddenConversations) more conversations awaiting review. Open Gmail to see the rest.")
    }

    /// Bulk actions reach every retained message, including the ones the menu
    /// has no room to show, so the count is stated before the action runs.
    static func bulkActionScope(retainedMessages: Int) -> String {
        if retainedMessages == 1 {
            return String(localized: "Applies to 1 retained message")
        }
        return String(localized: "Applies to \(retainedMessages) retained messages")
    }

    static func reviewCountText(_ count: Int) -> String {
        switch count {
        case 0:
            String(localized: "No messages")
        case 1:
            String(localized: "1 message")
        default:
            String(localized: "\(count) messages")
        }
    }

    static func menuBarAccessibilityLabel(
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

enum AccountRecoveryAction: Equatable {
    case enable
    case reconnect
    case signInAgain

    var title: String {
        switch self {
        case .enable:
            String(localized: "Enable Account")
        case .reconnect:
            String(localized: "Reconnect")
        case .signInAgain:
            String(localized: "Sign in Again")
        }
    }

    var requiresAuthorizationSlot: Bool {
        self == .signInAgain
    }

    static func needed(for state: AccountRuntimeState) -> AccountRecoveryAction? {
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

enum AccountPresentation {
    static func menuTitle(for state: AccountRuntimeState) -> String {
        String(localized: "\(statusText(for: state)) • \(state.account.email)")
    }

    static func menuIconSystemName(for state: AccountRuntimeState) -> String {
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

    static func canRefresh(_ states: [AccountRuntimeState]) -> Bool {
        states.contains { $0.account.isEnabled }
    }

    static func statusText(for state: AccountRuntimeState) -> String {
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

    static func detailText(for state: AccountRuntimeState, includeSpam: Bool = false) -> String {
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
