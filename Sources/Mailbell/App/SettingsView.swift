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
            "General"
        case .notifications:
            "Notifications"
        case .accounts:
            "Accounts"
        case .about:
            "About"
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
    @ObservedObject var appState: AppState
    @State var launchAtLogin = LoginItem.isEnabled
    @State var loginItemStatus = LoginItem.status
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
            Button("Remove Account", role: .destructive) {
                if let account = accountPendingRemoval {
                    appState.removeAccount(accountID: account.id)
                    accountPendingRemoval = nil
                }
            }
            Button("Cancel", role: .cancel) {
                accountPendingRemoval = nil
            }
        } message: {
            Text(
                "Mailbell deletes this account's sign-in from your Keychain and stops watching it. "
                    + "Nothing in Gmail changes, and no mail is deleted."
            )
        }
    }

    var generalTab: some View {
        Form {
            pendingCountSection
            startupSection
            updatesSection
            restoreDefaultsSection
        }
        .formStyle(.grouped)
    }

    var notificationsTab: some View {
        Form {
            notificationStatusSection
            notificationActionsSection
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
            .font(.footnote)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
    }

    var loginItemStatusValue: SettingsStatusValue {
        switch loginItemStatus {
        case .enabled:
            SettingsStatusValue(loginItemStatus.title, tone: .success, context: "Login item")
        case .disabled:
            SettingsStatusValue(loginItemStatus.title, tone: .inactive, context: "Login item")
        case .requiresApproval, .unavailable:
            SettingsStatusValue(loginItemStatus.title, tone: .warning, context: "Login item")
        }
    }

    /// The toggle already reports the ordinary case. A separate status row earns
    /// its space only when the system disagrees with what the toggle says.
    var loginItemNeedsAttention: Bool {
        loginItemStatus == .requiresApproval || loginItemStatus == .unavailable
    }

    func refreshBehaviorState() {
        appState.refreshNotificationAuthorizationState()
        refreshLoginItemStatus()
    }

    @MainActor
    func refreshLoginItemStatus() {
        loginItemStatus = LoginItem.status
        launchAtLogin = loginItemStatus == .enabled || loginItemStatus == .requiresApproval
    }

    func pendingCount(accountID: UUID) -> Int {
        appState.pendingCount(accountID: accountID)
    }
}
