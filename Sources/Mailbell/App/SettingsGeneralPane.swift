import AppKit
import SwiftUI
import UserNotifications

/// Menu bar presentation, startup, and Restore Defaults.
extension SettingsView {
    var pendingCountSection: some View {
        Section {
            Toggle(
                "Show review count",
                isOn: Binding(
                    get: { appState.showPendingCount },
                    set: { appState.setShowPendingCount($0) }
                )
            )
        } header: {
            Text("Menu Bar")
        } footer: {
            settingsFooter(
                "Shows the number of messages awaiting review in the menu bar."
            )
        }
    }

    var startupSection: some View {
        Section {
            Toggle("Start at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, newValue in
                    LoginItem.set(newValue)
                    refreshLoginItemStatus()
                }

            LabeledContent("Login item") {
                loginItemStatusValue
            }

            if loginItemStatus == .requiresApproval || loginItemStatus == .unavailable {
                LabeledContent("System Settings") {
                    Button("Open System Settings") {
                        SystemSettings.open()
                    }
                }
            }
        } header: {
            Text("Startup")
        } footer: {
            settingsFooter(loginItemStatus.detail)
        }
    }

    var restoreDefaultsSection: some View {
        Section {
            LabeledContent("Reset menu bar and mail preferences") {
                Button("Restore Defaults…", role: .destructive) {
                    showsRestoreDefaultsConfirmation = true
                }
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
                    "Menu bar and mail preferences return to their defaults. "
                        + "Your Gmail accounts, sign-ins, login item, and notification permission are not affected."
                )
            }
        } header: {
            Text("Reset")
        } footer: {
            settingsFooter("Restores every preference on this pane and under Advanced.")
        }
    }
}
