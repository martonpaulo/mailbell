import AppKit
import SwiftUI
import UserNotifications

/// How Mailbell presents itself: menu bar, startup, updates, and reset.
extension SettingsView {
    var pendingCountSection: some View {
        Section {
            Toggle(
                "Show the number of messages awaiting review",
                isOn: Binding(
                    get: { appState.showPendingCount },
                    set: { appState.setShowPendingCount($0) }
                )
            )
        } header: {
            Text("Menu Bar")
        } footer: {
            settingsFooter(
                "The bell is always visible. Turn this off to keep the menu bar quiet and see the count "
                    + "only when you open the menu."
            )
        }
    }

    var startupSection: some View {
        Section {
            Toggle("Open Mailbell at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, newValue in
                    LoginItem.set(newValue)
                    refreshLoginItemStatus()
                }

            if loginItemNeedsAttention {
                LabeledContent("Login item") {
                    loginItemStatusValue
                }

                Button("Open Login Items Settings") {
                    SystemSettings.open()
                }
            }
        } header: {
            Text("Startup")
        } footer: {
            settingsFooter(loginItemStatus.detail)
        }
    }

    var updatesSection: some View {
        Section {
            Toggle(
                "Automatically check for updates",
                isOn: Binding(
                    get: { appState.automaticallyChecksForUpdates },
                    set: { appState.setAutomaticallyChecksForUpdates($0) }
                )
            )
            .disabled(!appState.isUpdaterAvailable)

            Button("Check for Updates Now") {
                appState.checkForUpdates()
            }
            .disabled(!appState.isUpdaterAvailable)
        } header: {
            Text("Updates")
        } footer: {
            settingsFooter(updatesFooterText)
        }
    }

    var updatesFooterText: String {
        guard appState.isUpdaterAvailable else {
            return "Updates apply to an installed release of Mailbell, not to development builds."
        }
        return "Mailbell \(appVersionText) is installed. Updates come from GitHub Releases and are "
            + "checked against Mailbell's signature before they replace the app. "
            + "Update checks never include Gmail data."
    }

    var restoreDefaultsSection: some View {
        Section {
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
                        + "Your Gmail accounts, sign-ins, login item, and notification permission are not affected."
                )
            }
        } header: {
            Text("Reset")
        } footer: {
            settingsFooter(
                "Resets Mailbell's own preferences. Nothing is removed from Gmail and no account is disconnected."
            )
        }
    }
}
