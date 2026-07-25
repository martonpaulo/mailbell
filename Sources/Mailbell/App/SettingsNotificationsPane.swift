import AppKit
import SwiftUI
import UserNotifications

/// Whether macOS actually lets Mailbell's alerts through, and the controls that
/// change that.
extension SettingsView {
    var notificationStatusSection: some View {
        Section {
            SettingsRow(
                title: SettingsCopy.Notifications.statusTitle,
                description: SettingsCopy.Notifications.statusDescription(
                    needsAttention: notificationNeedsAttention,
                    detail: appState.notificationAuthorizationState.detail
                )
            ) {
                notificationPermissionStatus
            }

            SettingsRow(title: SettingsCopy.Notifications.alertsTitle) {
                notificationSettingStatusValue(
                    appState.notificationAuthorizationState.alertSetting,
                    context: SettingsCopy.Notifications.alertsTitle
                )
            }

            SettingsRow(title: SettingsCopy.Notifications.soundTitle) {
                notificationSettingStatusValue(
                    appState.notificationAuthorizationState.soundSetting,
                    context: SettingsCopy.Notifications.soundTitle
                )
            }

            SettingsRow(title: SettingsCopy.Notifications.badgeTitle) {
                notificationSettingStatusValue(
                    appState.notificationAuthorizationState.badgeSetting,
                    context: SettingsCopy.Notifications.badgeTitle
                )
            }

            // Section-scoped: the actions that change the status above, inside
            // the same box as their own last row.
            if notificationNeedsAttention {
                SettingsActionRow {
                    if appState.notificationAuthorizationState.canRequestPermission {
                        Button(SettingsCopy.Notifications.allow) {
                            appState.requestNotificationAuthorization()
                        }
                    }

                    if appState.notificationAuthorizationState.shouldOpenSystemSettings {
                        Button(SettingsCopy.Notifications.openSystemSettings) {
                            SystemSettings.open()
                        }
                    }
                }
            }
        } header: {
            Text(SettingsCopy.Notifications.sectionTitle)
        } footer: {
            // Pane-scoped verification actions, below the box.
            settingsFooter(notificationActionsFooterText) {
                if appState.isSendingTestNotification {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel(SettingsCopy.Notifications.sendingTestAccessibilityLabel)
                }

                Button(SettingsCopy.Notifications.refreshStatus) {
                    appState.refreshNotificationAuthorizationState(showStatusMessage: true)
                }

                Button(SettingsCopy.Notifications.sendTest) {
                    appState.sendTestNotification()
                }
                .disabled(appState.isSendingTestNotification)
            }
        }
    }

    var notificationPermissionStatus: SettingsStatusValue {
        let state = appState.notificationAuthorizationState
        let context = SettingsCopy.Notifications.statusTitle
        guard state.isBundled else {
            return SettingsStatusValue(state.summary, tone: .warning, context: context)
        }

        switch state.status {
        case .authorized, .provisional, .ephemeral:
            return SettingsStatusValue(state.summary, tone: .success, context: context)
        case .denied:
            return SettingsStatusValue(state.summary, tone: .error, context: context)
        case .notDetermined:
            return SettingsStatusValue(state.summary, tone: .warning, context: context)
        @unknown default:
            return SettingsStatusValue(state.summary, tone: .warning, context: context)
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
        SettingsCopy.Notifications.footer(
            isSendingTest: appState.isSendingTestNotification,
            testMessage: appState.notificationTestMessage,
            statusMessage: appState.notificationStatusMessage
        )
    }

    var notificationNeedsAttention: Bool {
        !appState.notificationAuthorizationState.canPostAlert
    }
}
