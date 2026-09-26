extension MonitorStatus {
    public var clearsLastError: Bool {
        switch self {
        case .signedOut, .connected:
            true
        case .connecting, .reconnecting, .signInRequired, .error:
            false
        }
    }
}
