extension MonitorStatus {
    var clearsLastError: Bool {
        switch self {
        case .signedOut, .connected:
            true
        case .connecting, .reconnecting, .reauthRequired, .error:
            false
        }
    }
}
