import AppKit
import SwiftUI
import UserNotifications

/// Whether macOS actually lets Mailbell's alerts through, and the controls that
/// change that.
extension SettingsView {
    var notificationStatusSection: some View {
        Section {
            SettingsRow(title: "Mailbell notifications", description: notificationStatusDescription) {
                notificationPermissionStatus
            }

            SettingsRow(title: "Alerts") {
                notificationSettingStatusValue(appState.notificationAuthorizationState.alertSetting, context: "Alerts")
            }

            SettingsRow(title: "Sound") {
                notificationSettingStatusValue(appState.notificationAuthorizationState.soundSetting, context: "Sound")
            }

            SettingsRow(title: "Badge") {
                notificationSettingStatusValue(appState.notificationAuthorizationState.badgeSetting, context: "Badge")
            }

            // Section-scoped: the actions that change the status above, inside
            // the same box as their own last row.
            if notificationNeedsAttention {
                SettingsActionRow {
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
                }
            }
        } header: {
            Text("Permission")
        } footer: {
            // Pane-scoped verification actions, below the box.
            settingsFooter(notificationActionsFooterText) {
                if appState.isSendingTestNotification {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Sending test notification")
                }

                Button("Refresh Status") {
                    appState.refreshNotificationAuthorizationState(showStatusMessage: true)
                }

                Button("Send Test Notification") {
                    appState.sendTestNotification()
                }
                .disabled(appState.isSendingTestNotification)
            }
        }
    }

    var notificationStatusDescription: String {
        guard notificationNeedsAttention else {
            return "Alerts, sound, and badge follow whatever you set for Mailbell in System Settings."
        }
        return appState.notificationAuthorizationState.detail
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

    var notificationNeedsAttention: Bool {
        !appState.notificationAuthorizationState.canPostAlert
    }
}
