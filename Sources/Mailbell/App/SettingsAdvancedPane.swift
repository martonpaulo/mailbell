import AppKit
import SwiftUI
import UserNotifications

/// Spam inclusion, per-account webmail routing, and build diagnostics.
extension SettingsView {
    var spamSection: some View {
        Section {
            Toggle(
                "Include spam",
                isOn: Binding(
                    get: { appState.includeSpam },
                    set: { appState.setIncludeSpam($0) }
                )
            )
        } header: {
            Text("Spam")
        } footer: {
            settingsFooter(
                "When enabled, unread Spam can appear in alerts and the review count. "
                    + "When disabled, Mailbell ignores Spam and removes existing Spam messages awaiting review."
            )
        }
    }

    @ViewBuilder
    var webmailSections: some View {
        if appState.accounts.isEmpty {
            Section {
                LabeledContent("Open with") {
                    Text("Add a Gmail account")
                }
            } header: {
                Text("Webmail")
            } footer: {
                settingsFooter("Webmail routing is configured per Gmail account.")
            }
        } else {
            ForEach(appState.accounts) { state in
                Section {
                    AccountWebmailSettingsView(
                        appState: appState,
                        accountState: state,
                        browsers: webmailBrowsers,
                        chromeProfiles: chromeProfiles
                    )
                } header: {
                    Text("Gmail Opening")
                } footer: {
                    settingsFooter(webmailFooterText(for: state))
                }
            }
        }
    }

    @ViewBuilder
    var oauthSetupSection: some View {
        if let setupMessage = appState.oauthSetupMessage {
            Section {
                OAuthSetupPanel(details: setupMessage)
            } header: {
                Text("Build Configuration")
            } footer: {
                settingsFooter(
                    "Mailbell signs in with a Google Desktop OAuth client that is compiled into the app bundle."
                )
            }
        }
    }

    func webmailFooterText(for state: AccountRuntimeState) -> String {
        var lines = [
            "Choose the browser or Chrome profile already signed in to this Gmail account."
        ]
        if let error = state.webmailOpenError {
            lines.append(error)
        }
        return lines.joined(separator: "\n")
    }

    func loadWebmailOptionsIfNeeded() async {
        guard !didLoadWebmailOptions else { return }
        didLoadWebmailOptions = true
        webmailBrowsers = BrowserRegistry.browsers()
        chromeProfiles = await ChromeProfileStore.loadProfilesAsync()
    }
}
