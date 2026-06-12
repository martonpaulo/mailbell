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
    @Published private(set) var manualRefreshMessage: String?
    @Published private(set) var emailStoreItems: [EmailStoreItem] = []
    @Published private(set) var menuBarIconSystemImage = "bell"

    private let supervisor: AccountSupervisor
    private var notificationAuthorizationTask: Task<Void, Never>?

    init() {
        supervisor = AccountSupervisor()
        supervisor.delegate = self
        accounts = supervisor.accountStates
        status = supervisor.aggregateStatus
        emailStoreItems = supervisor.emailStoreItems
        menuBarIconSystemImage = supervisor.menuBarIconSystemImage
        oauthSetupMessage = supervisor.oauthSetupMessage

        NotificationManager.shared.emailOpenHandler = { [weak self] emailID, accountID, url in
            await self?.supervisor.openEmail(id: emailID, accountID: accountID, url: url)
        }
        NotificationManager.shared.emailDismissHandler = { [weak self] emailID in
            self?.supervisor.dismissEmail(id: emailID)
        }
        NotificationManager.shared.webmailOpenHandler = { [weak self] accountID, url in
            await self?.supervisor.openWebmail(accountID: accountID, url: url)
        }
        refreshNotificationAuthorizationState()
    }

    deinit {
        notificationAuthorizationTask?.cancel()
    }

    var hasAccounts: Bool {
        !accounts.isEmpty
    }

    var canRequestManualRefresh: Bool {
        hasAccounts && !isAuthorizing
    }

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

    func openEmail(id: String) {
        Task {
            await supervisor.openEmail(id: id)
        }
    }

    func dismissEmail(id: String) {
        supervisor.dismissEmail(id: id)
    }

    func refreshNotificationAuthorizationState() {
        notificationAuthorizationTask?.cancel()
        notificationAuthorizationTask = Task { [weak self] in
            let state = await NotificationManager.shared.authorizationState()
            guard !Task.isCancelled else { return }
            self?.applyNotificationAuthorizationState(state)
        }
    }

    func requestNotificationAuthorization() {
        notificationAuthorizationTask?.cancel()
        notificationAuthorizationTask = Task { [weak self] in
            let state = await NotificationManager.shared.requestAuthorization()
            guard !Task.isCancelled else { return }
            self?.applyNotificationAuthorizationState(state)
        }
    }

    func refreshMailNow() {
        let result = supervisor.refreshNow()
        manualRefreshMessage = result.message
    }

    func sendTestNotification() {
        Task {
            let result = await NotificationManager.shared.notifyTest(account: accounts.first?.account)
            let state = await NotificationManager.shared.authorizationState()
            applyNotificationAuthorizationState(state)
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

    private func applyNotificationAuthorizationState(_ state: NotificationAuthorizationState) {
        guard notificationAuthorizationState != state else { return }
        notificationAuthorizationState = state
    }
}

extension AppState: AccountSupervisorDelegate {
    func accountSupervisorDidUpdate(states: [AccountRuntimeState], aggregateStatus: MonitorStatus) {
        accounts = states
        status = aggregateStatus
        emailStoreItems = supervisor.emailStoreItems
        menuBarIconSystemImage = supervisor.menuBarIconSystemImage
        oauthSetupMessage = supervisor.oauthSetupMessage
    }
}
