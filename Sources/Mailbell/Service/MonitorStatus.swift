import Foundation

enum MonitorStatus: Equatable {
    case signedOut
    case connecting
    case connected
    case reconnecting
    case reauthRequired
    case error

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
