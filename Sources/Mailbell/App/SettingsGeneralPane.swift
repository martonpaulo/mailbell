import AppKit
import SwiftUI

/// How Mailbell presents itself: menu bar, startup, and updates. Restore
/// Defaults is pane-scoped, so it sits below every box.
extension SettingsView {
    var pendingCountSection: some View {
        Section {
            SettingsToggleRow(
                title: SettingsCopy.MenuBar.showCountTitle,
                description: SettingsCopy.MenuBar.showCountDescription,
                isOn: Binding(
                    get: { appState.showPendingCount },
                    set: { appState.setShowPendingCount($0) }
                )
            )
        } header: {
            Text(SettingsCopy.MenuBar.sectionTitle)
        }
    }

    var startupSection: some View {
        Section {
            SettingsToggleRow(
                title: SettingsCopy.Startup.openAtLoginTitle,
                description: SettingsCopy.Startup.openAtLoginDescription,
                isOn: $launchAtLogin
            )
            .onChange(of: launchAtLogin) { _, newValue in
                LoginItem.set(newValue)
                refreshLoginItemStatus()
            }

            if loginItemNeedsAttention {
                SettingsRow(
                    title: SettingsCopy.Startup.loginItemTitle,
                    description: loginItemStatus.detail
                ) {
                    loginItemStatusValue
                }

                // Section-scoped: inside the box, as its own last row.
                SettingsActionRow {
                    Button(SettingsCopy.Startup.openLoginItemsSettings) {
                        SystemSettings.open()
                    }
                }
            }
        } header: {
            Text(SettingsCopy.Startup.sectionTitle)
        }
    }

    var updatesSection: some View {
        Section {
            SettingsToggleRow(
                title: SettingsCopy.Updates.automaticTitle,
                description: SettingsCopy.Updates.description(isUpdaterAvailable: appState.isUpdaterAvailable),
                isOn: Binding(
                    get: { appState.automaticallyChecksForUpdates },
                    set: { appState.setAutomaticallyChecksForUpdates($0) }
                )
            )
            .disabled(!appState.isUpdaterAvailable)

            SettingsRow(title: SettingsCopy.Updates.installedVersionTitle) {
                Text(appVersionText)
                    .textSelection(.enabled)
            }

            SettingsActionRow {
                Button(SettingsCopy.Updates.checkNow) {
                    appState.checkForUpdates()
                }
                .disabled(!appState.isUpdaterAvailable)
            }
        } header: {
            Text(SettingsCopy.Updates.sectionTitle)
        } footer: {
            // Pane-scoped: below every box, the way "Advanced…" sits at the
            // bottom of Privacy & Security.
            settingsFooter(SettingsCopy.RestoreDefaults.footer) {
                Button(SettingsCopy.RestoreDefaults.action, role: .destructive) {
                    showsRestoreDefaultsConfirmation = true
                }
                .confirmationDialog(
                    SettingsCopy.RestoreDefaults.confirmTitle,
                    isPresented: $showsRestoreDefaultsConfirmation
                ) {
                    Button(SettingsCopy.RestoreDefaults.confirmAction, role: .destructive) {
                        appState.restoreDefaults()
                    }
                    Button(SettingsCopy.RestoreDefaults.cancel, role: .cancel) {}
                } message: {
                    Text(SettingsCopy.RestoreDefaults.confirmMessage)
                }
            }
        }
    }
}
