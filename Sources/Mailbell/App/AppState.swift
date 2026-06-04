import AppKit
import Foundation
import SwiftUI

/// Observable UI state. Owns account supervision and exposes user actions.
@MainActor
final class AppState: ObservableObject {
    @Published private(set) var status: MonitorStatus = .signedOut
    @Published private(set) var accounts: [AccountRuntimeState] = []
    @Published private(set) var lastError: String?

    private let supervisor: AccountSupervisor

    init() {
        supervisor = AccountSupervisor()
        supervisor.delegate = self
        accounts = supervisor.accountStates
        status = supervisor.aggregateStatus

        NotificationManager.shared.webmailOpenHandler = { [weak self] accountID, url in
            await self?.supervisor.openWebmail(accountID: accountID, url: url)
        }
        Task {
            _ = await NotificationManager.shared.requestAuthorizationIfNeeded()
        }
    }

    var hasAccounts: Bool { !accounts.isEmpty }

    func signIn() {
        addGoogleAccount()
    }

    func addGoogleAccount() {
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

    func updateWebmailPreference(accountID: UUID, preference: WebmailOpenPreference?) {
        supervisor.updateWebmailPreference(accountID: accountID, preference: preference)
    }

    func openGmail(accountID: UUID) {
        Task {
            await supervisor.openGmail(accountID: accountID)
        }
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
