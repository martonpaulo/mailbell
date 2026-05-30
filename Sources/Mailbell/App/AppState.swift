import Foundation
import AppKit
import SwiftUI

/// Observable UI state. Owns the `MailMonitor` and exposes user actions.
@MainActor
final class AppState: ObservableObject {
    enum Status: Equatable {
        case needsConfig
        case signedOut
        case connecting
        case connected
        case reconnecting
        case reauthRequired
        case error

        var menuLabel: String {
            switch self {
            case .needsConfig: return "Set up Google client"
            case .signedOut: return "Not connected"
            case .connecting: return "Connecting…"
            case .connected: return "Connected"
            case .reconnecting: return "Reconnecting…"
            case .reauthRequired: return "Reconnect needed"
            case .error: return "Error"
            }
        }

        var systemImage: String {
            switch self {
            case .connected: return "bell.fill"
            case .connecting, .reconnecting: return "bell.badge"
            case .reauthRequired, .error: return "bell.slash"
            case .needsConfig, .signedOut: return "bell"
            }
        }
    }

    @Published private(set) var status: Status = .signedOut
    @Published private(set) var accountEmail: String?
    @Published private(set) var lastError: String?
    @Published private(set) var lastNotifiedSubject: String?
    @Published private(set) var isConfigured: Bool

    private let monitor: MailMonitor

    init() {
        let config = OAuthConfig.load()
        self.isConfigured = config != nil
        self.monitor = MailMonitor(config: config)
        self.monitor.delegate = self
        self.accountEmail = monitor.accountEmail

        if config == nil {
            status = .needsConfig
        } else if monitor.hasSession {
            monitor.start()
        } else {
            status = .signedOut
        }
        NotificationManager.shared.requestAuthorization()
    }

    var isSignedIn: Bool { monitor.hasSession }

    /// Persists the Google client and applies it. Returns to a signed-out (ready)
    /// state so the user can sign in.
    func saveConfig(clientID: String, clientSecret: String) {
        let trimmedID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else { return }
        OAuthConfig.save(clientID: trimmedID, clientSecret: clientSecret)
        let config = OAuthConfig.load()
        isConfigured = config != nil
        monitor.reconfigure(config)
        if isConfigured, status == .needsConfig {
            status = .signedOut
        }
    }

    func signIn() {
        guard isConfigured else {
            lastError = "Add your Google Client ID in Settings first."
            return
        }
        monitor.signIn()
    }

    func disconnect() {
        monitor.disconnect()
        accountEmail = nil
    }

    func reconnect() {
        monitor.start()
    }

    func openGmail() {
        NSWorkspace.shared.open(URL(string: "https://mail.google.com/")!)
    }

    func quit() {
        NSApplication.shared.terminate(nil)
    }
}

extension AppState: MailMonitorDelegate {
    nonisolated func monitor(didChangeStatus status: AppState.Status, error: String?) {
        Task { @MainActor in
            self.status = status
            if let error { self.lastError = error }
        }
    }

    nonisolated func monitor(didUpdateAccount email: String?) {
        Task { @MainActor in self.accountEmail = email }
    }

    nonisolated func monitor(didNotify header: MessageHeader) {
        Task { @MainActor in self.lastNotifiedSubject = header.subject }
    }
}
