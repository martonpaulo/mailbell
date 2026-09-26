import Foundation

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
        case .signInRequired, .error:
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
        case .signInRequired:
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
        case .signInRequired:
            return String(localized: "Sign in again to resume monitoring.")
        case .error:
            return String(localized: "Check the error and reconnect.")
        }
    }
}
