import AppKit
import SwiftUI
import UserNotifications

/// Sparkle update state and the manual check.
extension SettingsView {
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

            LabeledContent("Version") {
                Text(appVersionText)
            }

            LabeledContent("Check for Updates") {
                Button("Check Now") {
                    appState.checkForUpdates()
                }
                .disabled(!appState.isUpdaterAvailable)
            }
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
        return "Updates are downloaded from GitHub Releases and verified before they replace the app. "
            + "Update checks never include Gmail data."
    }
}
