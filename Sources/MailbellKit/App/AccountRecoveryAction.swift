import Foundation

public enum AccountRecoveryAction: Equatable, Sendable {
    case enable
    case reconnect
    case signInAgain

    /// Menu command titles. Sign-in continues in the browser, so that command
    /// asks for more input and ends with an ellipsis.
    public var title: String {
        switch self {
        case .enable:
            String(localized: "Resume Watching")
        case .reconnect:
            String(localized: "Reconnect")
        case .signInAgain:
            String(localized: "Sign In Again…")
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
        case .signInRequired:
            return .signInAgain
        case .connecting, .connected, .reconnecting:
            return nil
        }
    }
}
