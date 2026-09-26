import AppKit
import SwiftUI
import UserNotifications

/// Four panes, each owning one coherent question:
/// how Mailbell presents itself, whether alerts get through, which mailboxes it
/// watches, and what it is. Nothing that belongs to one account is split across
/// two panes.
enum SettingsTab: CaseIterable, Identifiable {
    case general
    case notifications
    case accounts
    case about

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .general:
            String(localized: "General")
        case .notifications:
            String(localized: "Notifications")
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
        case .notifications:
            "bell"
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
    @State var accountPendingRemoval: MailAccount?
    @State var showsRestoreDefaultsConfirmation = false

    var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label(SettingsTab.general.title, systemImage: SettingsTab.general.systemImage)
                }

            notificationsTab
                .tabItem {
                    Label(SettingsTab.notifications.title, systemImage: SettingsTab.notifications.systemImage)
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
        .confirmationDialog(
            accountRemovalTitle,
            isPresented: accountRemovalBinding,
            titleVisibility: .visible
        ) {
            Button(SettingsCopy.Accounts.confirmRemoveAction, role: .destructive) {
                if let account = accountPendingRemoval {
                    appState.removeAccount(accountID: account.id)
                    accountPendingRemoval = nil
                }
            }
            Button(SettingsCopy.Accounts.cancel, role: .cancel) {
                accountPendingRemoval = nil
            }
        } message: {
            Text(SettingsCopy.Accounts.removeMessage)
        }
    }

    var generalTab: some View {
        Form {
            pendingCountSection
            startupSection
            updatesSection
        }
        .formStyle(.grouped)
    }

    var notificationsTab: some View {
        Form {
            notificationSoundSection
            notificationStatusSection
        }
        .formStyle(.grouped)
    }

    /// Everything about an account lives here, including where its mail opens,
    /// so a user never has to remember which pane holds which half.
    var accountsTab: some View {
        Form {
            accountOverviewSection
            watchedMailboxesSection
            accountSections
        }
        .formStyle(.grouped)
        .task {
            await loadWebmailOptionsIfNeeded()
        }
    }

    var aboutTab: some View {
        Form {
            aboutAppSection
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

    /// Explanatory text plus the section's own actions, rendered below the group
    /// box the way System Settings places a section-scoped button.
    func settingsFooter(
        _ text: String?,
        @ViewBuilder actions: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: Token.Space.sm) {
            if let text, !text.isEmpty {
                settingsFooter(text)
            }
            SettingsActionRow {
                actions()
            }
        }
    }

    func refreshBehaviorState() {
        appState.refreshNotificationAuthorizationState()
        appState.launchAtLogin.refresh()
    }

    func pendingCount(accountID: UUID) -> Int {
        appState.pendingCount(accountID: accountID)
    }
}
