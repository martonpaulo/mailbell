import Foundation

/// Whether macOS will let Mailbell's alerts through, and the test that proves
/// it. macOS owns the permission; this only reads it back and reports it.
@MainActor
extension AppState {
    /// Runs when Settings appears and whenever Mailbell becomes active, so a
    /// change made in System Settings shows up without a refresh button.
    func refreshNotificationAuthorizationState() {
        notificationAuthorizationTask?.cancel()
        let notificationManager = notificationManager
        notificationAuthorizationTask = Task { [weak self] in
            let state = await notificationManager.authorizationState()
            guard !Task.isCancelled else { return }
            self?.applyNotificationAuthorizationState(state)
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
            defer { isSendingTestNotification = false }
            let result = await notificationManager.notifyTest(account: accounts.first?.account)
            let state = await notificationManager.authorizationState()
            applyNotificationAuthorizationState(state)
            notificationTestMessage = result.userMessage ?? SettingsCopy.Notifications.testSent
        }
    }
}
