import AppKit
import SwiftUI

@main
struct MailbellApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()

    @SceneBuilder
    var body: some Scene {
        MenuBarExtra("Mailbell", systemImage: appState.menuBarIconSystemImage) {
            MenuContent(appState: appState)
        }

        Settings {
            SettingsView(appState: appState)
        }
    }
}

/// Keeps the app out of the Dock and app switcher (accessory style).
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        true
    }
}

struct MenuContent: View {
    @ObservedObject var appState: AppState

    var body: some View {
        Label(appState.status.menuLabel, systemImage: appState.status.systemImage)

        if appState.accounts.isEmpty {
            Label("No Gmail accounts", systemImage: "person.crop.circle.badge.exclamationmark")
        } else {
            Label(Self.accountSummary(for: appState.accounts), systemImage: "person.2")
        }

        Divider()

        if appState.accounts.isEmpty {
            Button {
                appState.addGoogleAccount()
            } label: {
                Label(appState.isAuthorizing ? "Authorizing..." : "Add Gmail Account", systemImage: "plus")
            }
            .disabled(appState.oauthSetupMessage != nil || appState.isAuthorizing)
            if appState.oauthSetupMessage != nil {
                Label("Google OAuth setup required", systemImage: "key.fill")
            }
        }

        if !appState.accounts.isEmpty {
            Divider()
            accountsSection
        }

        Divider()

        emailStoreSection

        Divider()

        Button {
            appState.refreshMailNow()
        } label: {
            Label("Refresh Gmail", systemImage: "arrow.clockwise")
        }
        .disabled(!appState.canRequestManualRefresh)

        Divider()

        SettingsLink {
            Label("Settings…", systemImage: "gear")
        }

        Button {
            appState.quit()
        } label: {
            Label("Quit Mailbell", systemImage: "power")
        }
    }

    private static func accountSummary(for states: [AccountRuntimeState]) -> String {
        let enabled = states.filter(\.account.isEnabled)
        guard !enabled.isEmpty else { return "All accounts disabled" }

        let connected = enabled.filter { $0.status == .connected }.count
        if connected == enabled.count {
            return "\(connected) \(Self.accountNoun(count: connected)) connected"
        }
        if connected > 0 {
            return "\(connected) of \(enabled.count) connected"
        }
        return "\(enabled.count) \(Self.accountNoun(count: enabled.count)) enabled"
    }

    private static func accountNoun(count: Int) -> String {
        count == 1 ? "account" : "accounts"
    }

    private var accountsSection: some View {
        Section("Accounts") {
            ForEach(appState.accounts) { accountState in
                Button {
                    appState.openGmail(accountID: accountState.account.id)
                } label: {
                    Label(accountState.account.email, systemImage: accountState.status.systemImage)
                }
            }
        }
    }

    private var emailStoreSection: some View {
        Section("Unread") {
            if appState.emailStoreItems.isEmpty {
                Label("No unread emails", systemImage: "tray")
            } else {
                ForEach(appState.emailStoreItems) { email in
                    Menu {
                        Label("From: \(email.sender)", systemImage: "person")
                        Label("Time: \(email.time)", systemImage: "clock")
                        Divider()
                        Button {
                            appState.dismissEmail(id: email.id)
                        } label: {
                            Label("Dismiss", systemImage: "xmark.circle")
                        }
                        Button {
                            appState.openEmail(id: email.id)
                        } label: {
                            Label("Open", systemImage: "arrow.up.forward.square")
                        }
                    } label: {
                        Label(email.title, systemImage: "envelope")
                    }
                }
            }
        }
    }
}

struct SettingsView: View {
    @ObservedObject var appState: AppState
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginItemStatus = LoginItem.status

    var body: some View {
        Form {
            notificationSection
            startupSection
            accountsSection
        }
        .onAppear {
            refreshBehaviorState()
        }
    }

    private var notificationSection: some View {
        Section("Notifications") {
            LabeledContent("Status") {
                Label(
                    appState.notificationAuthorizationState.summary,
                    systemImage: appState.notificationAuthorizationState.canPostAlert
                        ? "bell.badge.fill"
                        : "bell.slash"
                )
            }

            Text(appState.notificationAuthorizationState.detail)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            ControlGroup {
                Button("Refresh Gmail") {
                    appState.refreshMailNow()
                }
                .disabled(!appState.canRequestManualRefresh)

                Button("Refresh Notification Status") {
                    appState.refreshNotificationAuthorizationState()
                }

                Button("Test Notification") {
                    appState.sendTestNotification()
                }

                if appState.notificationAuthorizationState.canRequestPermission {
                    Button("Request Notification Permission") {
                        appState.requestNotificationAuthorization()
                    }
                }

                if appState.notificationAuthorizationState.shouldOpenSystemSettings {
                    Button("Open System Settings") {
                        SystemSettings.open()
                    }
                }
            }

            if let message = appState.manualRefreshMessage {
                Label(message, systemImage: "arrow.clockwise")
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            if let message = appState.notificationTestMessage {
                Label(message, systemImage: "bell.badge")
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    private var startupSection: some View {
        Section("Startup") {
            Toggle("Start at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, newValue in
                    LoginItem.set(newValue)
                    refreshLoginItemStatus()
                }

            LabeledContent("Login item") {
                Label(
                    loginItemStatus.title,
                    systemImage: loginItemStatus == .enabled ? "checkmark.circle.fill" : "info.circle"
                )
            }

            Text(loginItemStatus.detail)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            if loginItemStatus == .requiresApproval || loginItemStatus == .unavailable {
                Button("Open System Settings") {
                    SystemSettings.open()
                }
            }
        }
    }

    private var accountsSection: some View {
        Section("Accounts") {
            if let setupMessage = appState.oauthSetupMessage {
                OAuthSetupPanel(details: setupMessage)
            }

            Button("Add Gmail Account") {
                appState.addGoogleAccount()
            }
            .disabled(appState.oauthSetupMessage != nil || appState.isAuthorizing)
            .help(appState.isAuthorizing ? "Complete Google sign-in in your browser." : "Add a Gmail account.")

            if appState.accounts.isEmpty {
                Label("No accounts connected", systemImage: "person.crop.circle.badge.exclamationmark")
                Text(accountEmptyDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(appState.accounts) { accountState in
                    accountRow(accountState)
                }
            }

            if let error = appState.lastError {
                accountErrorLabel(error)
            }
        }
    }

    private func accountRow(_ state: AccountRuntimeState) -> some View {
        Group {
            LabeledContent {
                ControlGroup {
                    Button("Open Gmail") {
                        appState.openGmail(accountID: state.account.id)
                    }

                    AccountActionsMenu(appState: appState, accountState: state)
                }
            } label: {
                Label(state.account.email, systemImage: state.status.systemImage)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }

            Text("\(state.account.providerID.displayName) · \(accountDetail(for: state))")
                .font(.caption)
                .foregroundStyle(.secondary)

            AccountWebmailSettingsView(appState: appState, accountState: state)

            if let error = state.lastError {
                accountErrorLabel(error)
            }
        }
    }

    private func accountErrorLabel(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .textSelection(.enabled)
    }

    private var accountEmptyDetail: String {
        if appState.oauthSetupMessage != nil {
            return "Set up your local Google OAuth credentials before adding an account."
        }
        if appState.isAuthorizing {
            return "Complete Google sign-in in your browser."
        }
        return "Add a Gmail account to start watching Inbox."
    }

    private func accountDetail(for state: AccountRuntimeState) -> String {
        guard state.account.isEnabled else { return "Disabled." }
        switch state.status {
        case .signedOut:
            return "Ready."
        case .connecting:
            return "Connecting."
        case .connected:
            return "Watching Inbox."
        case .reconnecting:
            return "Reconnecting."
        case .reauthRequired:
            return "Sign in again."
        case .error:
            return "Needs attention."
        }
    }

    private func refreshBehaviorState() {
        appState.refreshNotificationAuthorizationState()
        refreshLoginItemStatus()
    }

    private func refreshLoginItemStatus() {
        loginItemStatus = LoginItem.status
        launchAtLogin = loginItemStatus == .enabled || loginItemStatus == .requiresApproval
    }
}
