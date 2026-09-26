import Foundation

/// Whether macOS will let Mailbell's alerts through, and the test that proves
/// it. macOS owns the permission; this only reads it back and reports it.
@MainActor
extension AppState {
    func refreshNotificationAuthorizationState(showStatusMessage: Bool = false) {
        notificationAuthorizationTask?.cancel()
        let notificationManager = notificationManager
        notificationAuthorizationTask = Task { [weak self] in
            let state = await notificationManager.authorizationState()
            guard !Task.isCancelled else { return }
            self?.applyNotificationAuthorizationState(state)
            if showStatusMessage {
                self?.notificationTestMessage = nil
                self?.notificationStatusMessage = String(localized: "Notification permission refreshed.")
            }
        }
    }

    func requestNotificationAuthorization() {
        notificationAuthorizationTask?.cancel()
        let notificationManager = notificationManager
        notificationAuthorizationTask = Task { [weak self] in
            let state = await notificationManager.requestAuthorization()
            guard !Task.isCancelled else { return }
            self?.applyNotificationAuthorizationState(state)
            self?.notificationTestMessage = nil
            self?.notificationStatusMessage = nil
        }
    }

    func refreshMailNow() {
        let result = supervisor.refreshNow()
        manualRefreshMessage = result.message
    }

    func sendTestNotification() {
        guard !isSendingTestNotification else { return }
        Task {
            isSendingTestNotification = true
            notificationTestMessage = nil
            notificationStatusMessage = nil
            defer { isSendingTestNotification = false }
            let result = await notificationManager.notifyTest(account: accounts.first?.account)
            let state = await notificationManager.authorizationState()
            applyNotificationAuthorizationState(state)
            if let message = result.userMessage {
                notificationTestMessage = message
            } else {
                notificationTestMessage = String(localized: "Test notification sent.")
            }
        }
    }
}
