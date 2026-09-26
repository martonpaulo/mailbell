import Foundation

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
