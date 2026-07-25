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
    static let menuSectionTitle = "Awaiting Review"
    static let emptyMenuTitle = "No messages"
    static let openActionTitle = "Open"
    static let markAsReadActionTitle = "Mark as Read"
    static let dismissActionTitle = "Dismiss"
    static let bulkActionsMenuTitle = "All Messages"
    static let markAllAsReadActionTitle = "Mark All as Read"
    static let markingAllAsReadActionTitle = "Marking All as Read…"
    static let dismissAllActionTitle = "Dismiss All"
    static let reviewSectionTitle = "Awaiting Review"

    static func reviewCountText(_ count: Int) -> String {
        switch count {
        case 0:
            "No messages"
        case 1:
            "1 message"
        default:
            "\(count) messages"
        }
    }

    static func menuBarAccessibilityLabel(
        count: Int,
        showsCount: Bool = true,
        needsAttention: Bool = false
    ) -> String {
        if needsAttention {
            return "Mailbell, sign in needed"
        }
        guard showsCount, count > 0 else { return "Mailbell" }
        return "Mailbell, \(count) \(count == 1 ? "message" : "messages") awaiting review"
    }
}

enum AccountRecoveryAction: Equatable {
    case enable
    case reconnect
    case signInAgain

    var title: String {
        switch self {
        case .enable:
            "Enable Account"
        case .reconnect:
            "Reconnect"
        case .signInAgain:
            "Sign in Again"
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
        "\(statusText(for: state)) • \(state.account.email)"
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
        guard state.account.isEnabled else { return "Disabled" }
        switch state.status {
        case .signedOut:
            return "Not connected"
        case .connecting:
            return "Connecting"
        case .connected:
            return "Connected"
        case .reconnecting:
            return "Reconnecting"
        case .reauthRequired:
            return "Sign in needed"
        case .error:
            return "Needs attention"
        }
    }

    static func detailText(for state: AccountRuntimeState, includeSpam: Bool = false) -> String {
        guard state.account.isEnabled else { return "Gmail monitoring is paused for this account." }
        switch state.status {
        case .signedOut:
            return "Not connected."
        case .connecting:
            return "Connecting."
        case .connected:
            return includeSpam ? "Monitoring Inbox and Spam." : "Monitoring Inbox."
        case .reconnecting:
            return "Reconnecting."
        case .reauthRequired:
            return "Sign in again to resume monitoring."
        case .error:
            return "Check the error and reconnect."
        }
    }
}
