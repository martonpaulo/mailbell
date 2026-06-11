import AppKit
import Foundation
import SwiftUI

/// Observable UI state. Owns account supervision and exposes user actions.
@MainActor
final class AppState: ObservableObject {
    @Published private(set) var status: MonitorStatus = .signedOut
    @Published private(set) var accounts: [AccountRuntimeState] = []
    @Published private(set) var lastError: String?
    @Published private(set) var oauthSetupMessage: String?
    @Published private(set) var isAuthorizing = false
    @Published private(set) var notificationAuthorizationState: NotificationAuthorizationState = .unbundled
    @Published private(set) var notificationTestMessage: String?

    private let supervisor: AccountSupervisor

    init() {
        supervisor = AccountSupervisor()
        supervisor.delegate = self
        accounts = supervisor.accountStates
        status = supervisor.aggregateStatus
        oauthSetupMessage = supervisor.oauthSetupMessage

        NotificationManager.shared.webmailOpenHandler = { [weak self] accountID, url in
            await self?.supervisor.openWebmail(accountID: accountID, url: url)
        }
        refreshNotificationAuthorizationState()
    }

    var hasAccounts: Bool { !accounts.isEmpty }

    func signIn() {
        addGoogleAccount()
    }

    func addGoogleAccount() {
        guard !isAuthorizing else { return }
        Task {
            isAuthorizing = true
            defer { isAuthorizing = false }
            do {
                try await supervisor.addGmailAccount()
                lastError = nil
                oauthSetupMessage = supervisor.oauthSetupMessage
            } catch {
                lastError = error.localizedDescription
                oauthSetupMessage = supervisor.oauthSetupMessage
            }
        }
    }

    func reauthenticate(accountID: UUID) {
        guard !isAuthorizing else { return }
        Task {
            isAuthorizing = true
            defer { isAuthorizing = false }
            do {
                try await supervisor.reauthenticate(accountID: accountID)
                lastError = nil
                oauthSetupMessage = supervisor.oauthSetupMessage
            } catch {
                lastError = error.localizedDescription
                oauthSetupMessage = supervisor.oauthSetupMessage
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

    func refreshNotificationAuthorizationState() {
        Task {
            notificationAuthorizationState = await NotificationManager.shared.authorizationState()
        }
    }

    func requestNotificationAuthorization() {
        Task {
            notificationAuthorizationState = await NotificationManager.shared.requestAuthorization()
        }
    }

    func sendTestNotification() {
        Task {
            let result = await NotificationManager.shared.notifyTest(account: accounts.first?.account)
            notificationAuthorizationState = await NotificationManager.shared.authorizationState()
            if let message = result.userMessage {
                notificationTestMessage = message
            } else {
                notificationTestMessage = "Test notification sent."
            }
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
        oauthSetupMessage = supervisor.oauthSetupMessage
    }
}
