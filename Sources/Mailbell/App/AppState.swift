import AppKit
import Foundation
import SwiftUI

/// Observable UI state. Owns account supervision and exposes user actions.
@MainActor
final class AppState: ObservableObject {
    @Published private(set) var status: MonitorStatus = .signedOut
    @Published private(set) var accounts: [AccountRuntimeState] = []
    @Published private(set) var lastError: String?
    @Published private(set) var isConfigured: Bool

    private let supervisor: AccountSupervisor

    init() {
        let config = OAuthConfig.load()
        isConfigured = config != nil
        supervisor = AccountSupervisor(config: config)
        supervisor.delegate = self
        accounts = supervisor.accountStates
        status = supervisor.aggregateStatus

        if config == nil {
            status = .needsConfig
        }
        Task {
            _ = await NotificationManager.shared.requestAuthorizationIfNeeded()
        }
    }

    var hasAccounts: Bool { !accounts.isEmpty }

    /// Persists the Google client and applies it. Returns to a signed-out (ready)
    /// state so the user can sign in.
    func saveConfig(clientID: String, clientSecret: String) {
        let trimmedID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else { return }
        OAuthConfig.save(clientID: trimmedID, clientSecret: clientSecret)
        let config = OAuthConfig.load()
        isConfigured = config != nil
        supervisor.reconfigure(config)
        lastError = nil
        if isConfigured, status == .needsConfig {
            status = .signedOut
        }
    }

    func signIn() {
        addGoogleAccount()
    }

    func addGoogleAccount() {
        guard isConfigured else {
            lastError = "Add your Google Client ID in Settings first."
            return
        }
        Task {
            do {
                try await supervisor.addGmailAccount()
                lastError = nil
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    func reauthenticate(accountID: UUID) {
        Task {
            do {
                try await supervisor.reauthenticate(accountID: accountID)
                lastError = nil
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    func setAccountEnabled(_ isEnabled: Bool, accountID: UUID) {
        supervisor.setEnabled(isEnabled, accountID: accountID)
    }

    func reconnect(accountID: UUID) {
        supervisor.reconnect(accountID: accountID)
    }

    func removeAccount(accountID: UUID) {
        supervisor.remove(accountID: accountID)
    }

    func quit() {
        NSApplication.shared.terminate(nil)
    }
}

extension AppState: AccountSupervisorDelegate {
    func accountSupervisorDidUpdate(states: [AccountRuntimeState], aggregateStatus: MonitorStatus) {
        accounts = states
        status = aggregateStatus
    }
}
