import Foundation

enum MonitorStatus: Equatable {
    case signedOut
    case connecting
    case connected
    case reconnecting
    case reauthRequired
    case error

    /// The account cannot recover on its own: the user has to sign in again or
    /// resolve a surfaced failure. Drives the menu bar alert icon.
    /// Attention whose only remedy is signing in again. Distinguished from
    /// ordinary errors, which Reconnect handles, so nothing tells the user to
    /// do the wrong thing.
    var needsSignIn: Bool {
        self == .reauthRequired
    }

    var needsAttention: Bool {
        switch self {
        case .reauthRequired, .error:
            true
        case .signedOut, .connecting, .connected, .reconnecting:
            false
        }
    }

    var sortPriority: Int {
        switch self {
        case .reauthRequired, .error:
            0
        case .connecting, .reconnecting:
            1
        case .connected:
            2
        case .signedOut:
            3
        }
    }
}
