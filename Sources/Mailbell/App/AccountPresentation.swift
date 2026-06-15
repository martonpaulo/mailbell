import Foundation

enum PendingCopy {
    static let menuSectionTitle = "Pending"
    static let emptyMenuTitle = "No pending emails"

    static func countText(_ count: Int) -> String {
        "\(count) pending"
    }

    static func menuBarAccessibilityLabel(count: Int) -> String {
        guard count > 0 else { return "Mailbell" }
        return "Mailbell, \(count) \(count == 1 ? "pending email" : "pending emails")"
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

    static func detailText(for state: AccountRuntimeState) -> String {
        guard state.account.isEnabled else { return "Mailbell is not watching this account." }
        switch state.status {
        case .signedOut:
            return "Ready to connect."
        case .connecting:
            return "Connecting to Gmail."
        case .connected:
            return "Watching Inbox."
        case .reconnecting:
            return "Reconnecting to Gmail."
        case .reauthRequired:
            return "Sign in again to resume notifications."
        case .error:
            return "Check the error and reconnect."
        }
    }

    static func compactTitle(for state: AccountRuntimeState) -> String {
        "\(statusText(for: state)) - \(state.account.email)"
    }

    static func multiAccountMenuTitle(for state: AccountRuntimeState, pendingCount: Int) -> String {
        "\(state.account.email) - \(statusText(for: state)) - \(PendingCopy.countText(pendingCount))"
    }
}
