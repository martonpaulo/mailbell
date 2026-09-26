import AppKit
import MailbellKit
import SwiftUI

/// Three panes, each owning one coherent question (docs/interface.md,
/// "Settings"): how Mailbell presents itself and whether alerts get through,
/// which mailboxes it watches, and what it is. Nothing that belongs to one
/// account is split across two panes.
///
/// The raw values are stable identifiers: a stored pane is restored by name,
/// never by position, so reordering or merging panes cannot reopen the wrong one.
enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case accounts
    case about

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .general:
            String(localized: "General")
        case .accounts:
            String(localized: "Accounts")
        case .about:
            String(localized: "About")
        }
    }

    var systemImage: String {
        switch self {
        case .general:
            "gearshape"
        case .accounts:
            "person.crop.circle"
        case .about:
            "info.circle"
        }
    }
}

struct SettingsView: View {
    let appState: AppState
    @State var webmailBrowsers: [BrowserCandidate] = []
    @State var chromeProfiles: [ChromeProfileCandidate] = []
    @State var didLoadWebmailOptions = false
    @State var accountShowingDetails: AccountDetailsTarget?
    @State var showsRestoreDefaultsConfirmation = false
    @State var showsQuitConfirmation = false

    var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label(SettingsTab.general.title, systemImage: SettingsTab.general.systemImage)
                }

            accountsTab
                .tabItem {
                    Label(SettingsTab.accounts.title, systemImage: SettingsTab.accounts.systemImage)
                }

            aboutTab
                .tabItem {
                    Label(SettingsTab.about.title, systemImage: SettingsTab.about.systemImage)
                }
        }
        .onAppear {
            refreshBehaviorState()
        }
    }

    var generalTab: some View {
        Form {
            appCardSection
            menuBarSection
            notificationsSection
            permissionsSection
            generalFooterSection
        }
        .formStyle(.grouped)
    }

    /// Everything about an account lives here, including where its mail opens,
    /// so a person never has to remember which pane holds which half.
    var accountsTab: some View {
        Form {
            accountsSection
            watchedMailboxesSection
        }
        .formStyle(.grouped)
        .sheet(item: accountDetailsBinding) { state in
            AccountDetailsSheet(
                appState: appState,
                accountID: state.id,
                browsers: webmailBrowsers,
                chromeProfiles: chromeProfiles
            )
        }
        .task {
            await loadWebmailOptionsIfNeeded()
        }
    }

    var aboutTab: some View {
        Form {
            aboutAppSection
            updatesSection
            aboutLinksSection
            aboutLegalSection
        }
        .formStyle(.grouped)
    }

    func settingsFooter(_ text: String) -> some View {
        Text(text)
            .font(Token.Font.footnote)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
    }

    func refreshBehaviorState() {
        appState.refreshNotificationAuthorizationState()
        appState.launchAtLogin.refresh()
    }
}
