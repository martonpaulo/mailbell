import Foundation

public enum MonitorStatus: Equatable, Sendable {
    case signedOut
    case connecting
    case connected
    case reconnecting
    case signInRequired
    case error

    /// The account cannot recover on its own: the user has to sign in again or
    /// resolve a surfaced failure. Drives the menu bar alert icon.
    /// Attention whose only remedy is signing in again. Distinguished from
    /// ordinary errors, which Reconnect handles, so nothing tells the user to
    /// do the wrong thing.
    public var needsSignIn: Bool {
        self == .signInRequired
    }

    public var needsAttention: Bool {
        switch self {
        case .signInRequired, .error:
            true
        case .signedOut, .connecting, .connected, .reconnecting:
            false
        }
    }

    public var sortPriority: Int {
        switch self {
        case .signInRequired, .error:
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
