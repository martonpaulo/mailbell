import AppKit
import MailbellKit
import SwiftUI

/// How Mailbell presents itself and whether its alerts get through, laid out
/// like WindowHop's General pane: the app card with its live status and Launch
/// at login, the menu bar, notifications, permissions last, and a footer box
/// with Restore Defaults… and Quit Mailbell….
extension SettingsView {
    var appCardSection: some View {
        let launchAtLogin = appState.launchAtLogin
        return Section {
            HStack(spacing: Token.Space.md) {
                AppIconImage(size: Token.Size.appCardIcon)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Token.Space.xxs) {
                    Text(SettingsCopy.AppCard.name)
                        .font(.headline)
                    Text(generalStatusText)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)

            // The binding, not onChange: the toggle shows the status macOS
            // reports, and only a click requests a change. A refreshed status
            // never flows back into a change handler.
            SettingsToggleRow(
                title: SettingsCopy.Startup.launchAtLoginTitle,
                isOn: Binding(
                    get: { launchAtLogin.status.isOn },
                    set: { launchAtLogin.request($0) }
                )
            )
            .disabled(!launchAtLogin.status.allowsChange)

            // Shown only when macOS disagrees with the toggle or cannot apply it.
            if let note = SettingsCopy.Startup.note(for: launchAtLogin.status, failed: launchAtLogin.failed) {
                SettingsStatusValue(note, tone: .warning, context: SettingsCopy.Startup.launchAtLoginTitle)
            }

            // Section-scoped: inside the box, as its own last row.
            if launchAtLogin.status.offersLoginItemsSettings {
                SettingsActionRow {
                    Button(SettingsCopy.Startup.openLoginItemsSettings) {
                        launchAtLogin.openLoginItemsSettings()
                    }
                }
            }
        }
    }

    var menuBarSection: some View {
        Section {
            SettingsToggleRow(
                title: SettingsCopy.MenuBar.showCountTitle,
                description: SettingsCopy.MenuBar.showCountDescription,
                isOn: Binding(
                    get: { appState.showsMenuBarCount },
                    set: { appState.setShowsMenuBarCount($0) }
                )
            )
        } header: {
            Text(SettingsCopy.MenuBar.sectionTitle)
        }
    }

    var notificationsSection: some View {
        Section {
            SettingsToggleRow(
                title: SettingsCopy.Notifications.playSoundsTitle,
                description: SettingsCopy.Notifications.playSoundsDescription,
                isOn: Binding(
                    get: { appState.playNotificationSounds },
                    set: { appState.setPlayNotificationSounds($0) }
                )
            )

            // Row-scoped: the test belongs to this row, so its button sits in it.
            SettingsRow(
                title: SettingsCopy.Notifications.testTitle,
                description: SettingsCopy.Notifications.testRowDescription(result: appState.notificationTestMessage)
            ) {
                SettingsActionRow {
                    if appState.isSendingTestNotification {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel(SettingsCopy.Notifications.sendingTestAccessibilityLabel)
                    }
                    Button(SettingsCopy.Notifications.sendTest) {
                        appState.sendTestNotification()
                    }
                    .disabled(appState.isSendingTestNotification)
                }
            }
        } header: {
            Text(SettingsCopy.Notifications.sectionTitle)
        }
    }

    /// Last, as WindowHop places Accessibility: whether macOS lets the alerts
    /// through. When it does not, the fix takes the place of the check mark.
    var permissionsSection: some View {
        let state = appState.notificationAuthorizationState
        return Section {
            SettingsRow(
                title: SettingsCopy.Permissions.notificationsTitle,
                description: SettingsCopy.Permissions.notificationsRowDescription(for: state)
            ) {
                notificationPermissionControl(for: state)
            }

            if state.alertsOff {
                SettingsRow(
                    title: SettingsCopy.Permissions.alertsTitle,
                    description: SettingsCopy.Permissions.alertsOffDescription
                ) {
                    SettingsStatusValue(
                        SettingsCopy.Permissions.off,
                        tone: .warning,
                        context: SettingsCopy.Permissions.alertsTitle
                    )
                }
            }

            if state.soundOff {
                SettingsRow(
                    title: SettingsCopy.Permissions.soundTitle,
                    description: SettingsCopy.Permissions.soundOffDescription
                ) {
                    SettingsStatusValue(
                        SettingsCopy.Permissions.off,
                        tone: .inactive,
                        context: SettingsCopy.Permissions.soundTitle
                    )
                }
            }

            if state.alertsOff || state.soundOff {
                SettingsActionRow {
                    Button(SettingsCopy.Permissions.openSystemSettings) {
                        SystemSettings.open()
                    }
                }
            }
        } header: {
            Text(SettingsCopy.Permissions.sectionTitle)
        }
    }

    @ViewBuilder
    func notificationPermissionControl(for state: NotificationAuthorizationState) -> some View {
        let value = SettingsCopy.Permissions.notificationsValue(for: state)
        let context = SettingsCopy.Permissions.notificationsTitle
        if state.canRequestPermission {
            Button(SettingsCopy.Permissions.allow) {
                appState.requestNotificationAuthorization()
            }
        } else if state.isDenied {
            Button(SettingsCopy.Permissions.openSystemSettings) {
                SystemSettings.open()
            }
        } else if state.isBundled {
            SettingsStatusValue(value, tone: .success, context: context)
        } else {
            SettingsStatusValue(value, tone: .inactive, context: context)
        }
    }

    /// A box of its own at the bottom, as in WindowHop: Restore Defaults…
    /// leading and Quit Mailbell… trailing. Neither loses data, so neither is
    /// styled as destructive; both confirm first and say what changes.
    var generalFooterSection: some View {
        Section {
            SettingsActionRow {
                Button(SettingsCopy.RestoreDefaults.action) {
                    showsRestoreDefaultsConfirmation = true
                }
                .confirmationDialog(
                    SettingsCopy.RestoreDefaults.confirmTitle,
                    isPresented: $showsRestoreDefaultsConfirmation
                ) {
                    Button(SettingsCopy.RestoreDefaults.confirmAction) {
                        appState.restoreDefaults()
                    }
                    Button(SettingsCopy.RestoreDefaults.cancel, role: .cancel) {}
                } message: {
                    Text(SettingsCopy.RestoreDefaults.confirmMessage)
                }
            } trailing: {
                Button(SettingsCopy.Quit.action) {
                    showsQuitConfirmation = true
                }
                .confirmationDialog(
                    SettingsCopy.Quit.confirmTitle,
                    isPresented: $showsQuitConfirmation
                ) {
                    Button(SettingsCopy.Quit.confirmAction) {
                        appState.quit()
                    }
                    Button(SettingsCopy.Quit.cancel, role: .cancel) {}
                } message: {
                    Text(SettingsCopy.Quit.confirmMessage)
                }
            }
        }
    }

    var generalStatusText: String {
        GeneralStatus.text(
            accounts: appState.accounts,
            conversationsToReview: appState.shownItems.count,
            notificationsDenied: appState.notificationAuthorizationState.isDenied
        )
    }
}
