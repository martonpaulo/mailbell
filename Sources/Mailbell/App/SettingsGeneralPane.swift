import AppKit
import SwiftUI
import UserNotifications

/// How Mailbell presents itself: menu bar, startup, and updates. Restore
/// Defaults is pane-scoped, so it sits below every box.
extension SettingsView {
    var pendingCountSection: some View {
        Section {
            Toggle(
                isOn: Binding(
                    get: { appState.showPendingCount },
                    set: { appState.setShowPendingCount($0) }
                )
            ) {
                SettingsRowLabel(
                    title: "Show the number of messages awaiting review",
                    description: "The bell is always visible. Turn this off to keep the menu bar quiet "
                        + "and see the count only when you open the menu."
                )
            }
        } header: {
            Text("Menu Bar")
        }
    }

    var startupSection: some View {
        Section {
            Toggle(isOn: $launchAtLogin) {
                SettingsRowLabel(
                    title: "Open Mailbell at login",
                    description: "Mailbell watches for mail only while it is running."
                )
            }
            .onChange(of: launchAtLogin) { _, newValue in
                LoginItem.set(newValue)
                refreshLoginItemStatus()
            }

            if loginItemNeedsAttention {
                SettingsRow(title: "Login item", description: loginItemStatus.detail) {
                    loginItemStatusValue
                }

                // Section-scoped: inside the box, as its own last row.
                SettingsActionRow {
                    Button("Open Login Items Settings") {
                        SystemSettings.open()
                    }
                }
            }
        } header: {
            Text("Startup")
        }
    }

    var updatesSection: some View {
        Section {
            Toggle(
                isOn: Binding(
                    get: { appState.automaticallyChecksForUpdates },
                    set: { appState.setAutomaticallyChecksForUpdates($0) }
                )
            ) {
                SettingsRowLabel(
                    title: "Automatically check for updates",
                    description: updatesDescription
                )
            }
            .disabled(!appState.isUpdaterAvailable)

            SettingsRow(title: "Installed version") {
                Text(appVersionText)
                    .textSelection(.enabled)
            }

            SettingsActionRow {
                Button("Check for Updates…") {
                    appState.checkForUpdates()
                }
                .disabled(!appState.isUpdaterAvailable)
            }
        } header: {
            Text("Updates")
        } footer: {
            // Pane-scoped: below every box, the way "Advanced…" sits at the
            // bottom of Privacy & Security.
            settingsFooter(restoreDefaultsFooterText) {
                Button("Restore Defaults…", role: .destructive) {
                    showsRestoreDefaultsConfirmation = true
                }
                .confirmationDialog(
                    "Restore all settings to their defaults?",
                    isPresented: $showsRestoreDefaultsConfirmation
                ) {
                    Button("Restore Defaults", role: .destructive) {
                        appState.restoreDefaults()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text(
                        "The menu bar count and watched mailboxes return to their defaults. "
                            + "Your Gmail accounts, sign-ins, login item, and notification permission "
                            + "are not affected."
                    )
                }
            }
        }
    }

    var updatesDescription: String {
        guard appState.isUpdaterAvailable else {
            return "Updates apply to an installed release of Mailbell, not to development builds."
        }
        return "Updates come from GitHub Releases and are checked against Mailbell's signature before "
            + "they replace the app. Update checks never include Gmail data."
    }

    var restoreDefaultsFooterText: String {
        "Restoring defaults resets Mailbell's own preferences only. Nothing is removed from Gmail and "
            + "no account is disconnected."
    }
}
