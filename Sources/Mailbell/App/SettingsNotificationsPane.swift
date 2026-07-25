import AppKit
import SwiftUI
import UserNotifications

/// macOS notification permission state and the controls that change it.
extension SettingsView {
    /// Status rows sit with the actions that change that status, so a user who
    /// sees "Denied" finds the fix without hunting through another section.
    var notificationStatusSection: some View {
        Section {
            LabeledContent("Status") {
                notificationPermissionStatus
            }

            LabeledContent("Alerts") {
                notificationSettingStatusValue(appState.notificationAuthorizationState.alertSetting, context: "Alerts")
            }

            LabeledContent("Sound") {
                notificationSettingStatusValue(appState.notificationAuthorizationState.soundSetting, context: "Sound")
            }

            LabeledContent("Badge") {
                notificationSettingStatusValue(appState.notificationAuthorizationState.badgeSetting, context: "Badge")
            }

            if appState.notificationAuthorizationState.canRequestPermission {
                Button("Allow Notifications…") {
                    appState.requestNotificationAuthorization()
                }
            }

            if appState.notificationAuthorizationState.shouldOpenSystemSettings {
                Button("Open Notification Settings") {
                    SystemSettings.open()
                }
            }
        } header: {
            Text("Permission")
        } footer: {
            settingsFooter(notificationFooterText)
        }
    }

    var notificationActionsSection: some View {
        Section {
            HStack(spacing: Token.Space.sm) {
                Button("Send a Test Notification") {
                    appState.sendTestNotification()
                }
                .disabled(appState.isSendingTestNotification)

                if appState.isSendingTestNotification {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Sending test notification")
                }
            }

            Button("Refresh Permission Status") {
                appState.refreshNotificationAuthorizationState(showStatusMessage: true)
            }
        } header: {
            Text("Check Delivery")
        } footer: {
            settingsFooter(notificationActionsFooterText)
        }
    }

    var notificationPermissionStatus: SettingsStatusValue {
        let state = appState.notificationAuthorizationState
        guard state.isBundled else {
            return SettingsStatusValue(state.summary, tone: .warning, context: "Notification permission")
        }

        switch state.status {
        case .authorized, .provisional, .ephemeral:
            return SettingsStatusValue(state.summary, tone: .success, context: "Notification permission")
        case .denied:
            return SettingsStatusValue(state.summary, tone: .error, context: "Notification permission")
        case .notDetermined:
            return SettingsStatusValue(state.summary, tone: .warning, context: "Notification permission")
        @unknown default:
            return SettingsStatusValue(state.summary, tone: .warning, context: "Notification permission")
        }
    }

    func notificationSettingStatusValue(
        _ setting: UNNotificationSetting,
        context: String
    ) -> SettingsStatusValue {
        switch setting {
        case .enabled:
            return SettingsStatusValue("Enabled", tone: .success, context: context)
        case .disabled:
            return SettingsStatusValue("Disabled", tone: .inactive, context: context)
        case .notSupported:
            return SettingsStatusValue("Not supported", tone: .inactive, context: context)
        @unknown default:
            return SettingsStatusValue("Unavailable", tone: .warning, context: context)
        }
    }

    var notificationActionsFooterText: String {
        if appState.isSendingTestNotification {
            return "Sending a test notification…"
        }
        if let message = appState.notificationTestMessage {
            return message
        }
        if let message = appState.notificationStatusMessage {
            return message
        }
        return "A test notification confirms macOS will actually show Mailbell's alerts. "
            + "Refresh after changing anything in System Settings."
    }

    var notificationFooterText: String {
        guard notificationNeedsAttention else {
            return "Alerts, sound, and badge follow whatever you set for Mailbell in System Settings."
        }
        return appState.notificationAuthorizationState.detail
    }

    var notificationNeedsAttention: Bool {
        !appState.notificationAuthorizationState.canPostAlert
    }
}
