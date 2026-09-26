import Foundation

public enum AccountPresentation {
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

    /// One short status per account, shown once: in the Settings row and in
    /// the menu. An account that reached Gmail says what it watches.
    public static func statusText(for state: AccountRuntimeState, includeSpam: Bool = false) -> String {
        guard state.account.isEnabled else { return String(localized: "Paused") }
        switch state.status {
        case .signedOut:
            return String(localized: "Not connected")
        case .connecting:
            return String(localized: "Connecting…")
        case .connected:
            return includeSpam
                ? String(localized: "Watching Inbox and Spam")
                : String(localized: "Watching Inbox")
        case .reconnecting:
            return String(localized: "Reconnecting…")
        case .signInRequired:
            return String(localized: "Sign-in needed")
        case .error:
            return String(localized: "Can't connect")
        }
    }

    /// The level a status dot shows beside `statusText`. The text always
    /// carries the state, so colour is never the only cue.
    public static func statusLevel(for state: AccountRuntimeState) -> AccountStatusLevel {
        guard state.account.isEnabled else { return .inactive }
        switch state.status {
        case .connected:
            return .active
        case .connecting, .reconnecting:
            return .progress
        case .signedOut:
            return .inactive
        case .signInRequired:
            return .warning
        case .error:
            return .error
        }
    }

    /// "2 accounts (1 needs sign-in)": how many accounts there are, and how many
    /// of the enabled ones need the person to sign in again.
    public static func overview(_ states: [AccountRuntimeState]) -> String {
        guard !states.isEmpty else { return String(localized: "No Gmail account") }
        let count =
            states.count == 1
            ? String(localized: "1 account")
            : String(localized: "\(states.count) accounts")
        let needingSignIn = states.filter { $0.account.isEnabled && $0.status.needsSignIn }.count
        guard needingSignIn > 0 else { return count }
        return needingSignIn == 1
            ? String(localized: "\(count) (1 needs sign-in)")
            : String(localized: "\(count) (\(needingSignIn) need sign-in)")
    }
}

/// How an account's status reads at a glance, for its status dot.
public enum AccountStatusLevel: Equatable, Sendable {
    case active
    case progress
    case inactive
    case warning
    case error
}
