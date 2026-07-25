import AppKit
import SwiftUI
import UserNotifications

/// macOS notification permission state and the controls that change it.
extension SettingsView {
    var notificationStatusSection: some View {
        Section {
            LabeledContent("Permission") {
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
        } header: {
            Text("Notifications")
        } footer: {
            settingsFooter(notificationFooterText)
        }
    }

    var notificationActionsSection: some View {
        Section {
            LabeledContent("Notification Status") {
                Button("Refresh") {
                    appState.refreshNotificationAuthorizationState(showStatusMessage: true)
                }
            }

            LabeledContent("Test Notification") {
                if appState.isSendingTestNotification {
                    SettingsProgressValue("Sending", context: "Test notification")
                } else {
                    Button("Send") {
                        appState.sendTestNotification()
                    }
                }
            }

            if appState.notificationAuthorizationState.canRequestPermission {
                LabeledContent("Permission Request") {
                    Button("Request") {
                        appState.requestNotificationAuthorization()
                    }
                }
            }

            if appState.notificationAuthorizationState.shouldOpenSystemSettings {
                LabeledContent("System Settings") {
                    Button("Open") {
                        SystemSettings.open()
                    }
                }
            }
        } header: {
            Text("Notification Controls")
        } footer: {
            notificationActionsFooter
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

    @ViewBuilder
    var notificationActionsFooter: some View {
        if appState.isSendingTestNotification {
            settingsFooter("Sending test notification…")
        } else {
            settingsFooter(notificationActionsFooterText)
        }
    }

    var notificationActionsFooterText: String {
        if let message = appState.notificationTestMessage {
            return message
        }
        if let message = appState.notificationStatusMessage {
            return message
        }
        return "Use Refresh after changing notification settings in macOS."
    }

    var notificationFooterText: String {
        guard notificationNeedsAttention else {
            return "Mailbell uses macOS notification settings for alerts, sound, and badge."
        }
        return appState.notificationAuthorizationState.detail
    }

    var notificationNeedsAttention: Bool {
        !appState.notificationAuthorizationState.canPostAlert
    }
}
