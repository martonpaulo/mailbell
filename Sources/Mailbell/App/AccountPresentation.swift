import Foundation

enum PendingCopy {
    static let menuSectionTitle = "Awaiting Review"
    static let emptyMenuTitle = "No messages"
    static let openActionTitle = "Open"
    static let markAsReadActionTitle = "Mark as Read"
    static let dismissActionTitle = "Dismiss"
    static let reviewSectionTitle = "Awaiting Review"

    static func countText(_ count: Int) -> String {
        reviewCountText(count)
    }

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

    static func menuBarAccessibilityLabel(count: Int, showsCount: Bool = true) -> String {
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
    static func webmailOpenLabel(email: String) -> String {
        email
    }

    static func menuTitle(for state: AccountRuntimeState) -> String {
        "\(statusText(for: state)) • \(state.account.email)"
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
