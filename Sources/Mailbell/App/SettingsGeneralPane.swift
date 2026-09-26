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
        let launchAtLogin = appState.launchAtLogin
        return Section {
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
