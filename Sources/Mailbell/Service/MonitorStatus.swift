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
        case .signedOut: "Not connected"
        case .connecting: "Connecting..."
        case .connected: "Connected"
        case .reconnecting: "Reconnecting..."
        case .reauthRequired: "Reconnect needed"
        case .error: "Error"
        }
    }

    var systemImage: String {
        switch self {
        case .connected: "bell.fill"
        case .connecting, .reconnecting: "bell.badge"
        case .reauthRequired, .error: "bell.slash"
        case .signedOut: "bell"
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
