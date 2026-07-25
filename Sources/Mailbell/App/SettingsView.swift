import AppKit
import SwiftUI
import UserNotifications

enum SettingsTab: CaseIterable, Identifiable {
    case general
    case notifications
    case accounts
    case advanced
    case updates
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
        case .advanced:
            "Advanced"
        case .updates:
            "Updates"
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
        case .advanced:
            "slider.horizontal.3"
        case .updates:
            "arrow.triangle.2.circlepath"
        case .about:
            "info.circle"
        }
    }
}

// swiftlint:disable:next type_body_length
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

            advancedTab
                .tabItem {
                    Label(SettingsTab.advanced.title, systemImage: SettingsTab.advanced.systemImage)
                }

            updatesTab
                .tabItem {
                    Label(SettingsTab.updates.title, systemImage: SettingsTab.updates.systemImage)
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
                "Mailbell will delete local tokens and stop notifications for this account. "
                    + "Gmail mail will not be changed."
            )
        }
    }

    var generalTab: some View {
        Form {
            pendingCountSection
            startupSection
            restoreDefaultsSection
        }
        .formStyle(.grouped)
    }

    var updatesTab: some View {
        Form {
            updatesSection
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

    var accountsTab: some View {
        Form {
            accountOverviewSection
            accountSections
        }
        .formStyle(.grouped)
    }

    var advancedTab: some View {
        Form {
            spamSection
            webmailSections
            oauthSetupSection
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
