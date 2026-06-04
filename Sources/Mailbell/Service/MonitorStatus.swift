import Foundation

enum MonitorStatus: Equatable {
    case signedOut
    case connecting
    case connected
    case reconnecting
    case reauthRequired
    case error

    var menuLabel: String {
        switch self {
        case .signedOut: return "Not connected"
        case .connecting: return "Connecting..."
        case .connected: return "Connected"
        case .reconnecting: return "Reconnecting..."
        case .reauthRequired: return "Reconnect needed"
        case .error: return "Error"
        }
    }

    var systemImage: String {
        switch self {
        case .connected: return "bell.fill"
        case .connecting, .reconnecting: return "bell.badge"
        case .reauthRequired, .error: return "bell.slash"
        case .signedOut: return "bell"
        }
    }

    var sortPriority: Int {
        switch self {
        case .reauthRequired, .error:
            return 0
        case .connecting, .reconnecting:
            return 1
        case .connected:
            return 2
        case .signedOut:
            return 3
        }
    }
}
