import AppKit
import SwiftUI

@main
struct MailbellApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()
    @AppStorage(AppPreferenceKeys.showMenuBarIcon) private var showMenuBarIcon = AppPreferences.defaultShowMenuBarIcon

    var body: some Scene {
        MenuBarExtra(isInserted: $showMenuBarIcon) {
            MenuContent(appState: appState)
        } label: {
            Image(systemName: appState.status.systemImage)
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
        guard !AppPreferences.showMenuBarIcon() else { return }
        SettingsWindow.openWhenReady()
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows || !AppPreferences.showMenuBarIcon() {
            SettingsWindow.openWhenReady()
        }
        return true
    }
}

struct MenuContent: View {
    @ObservedObject var appState: AppState

    var body: some View {
        Text(appState.status.menuLabel)

        if appState.accounts.isEmpty {
            Text("No accounts")
        } else {
            Text(Self.accountSummary(for: appState.accounts))
        }

        Divider()

        if appState.accounts.isEmpty {
            Button(appState.isAuthorizing ? "Authorizing..." : "Add Gmail Account") {
                appState.addGoogleAccount()
            }
            .disabled(appState.oauthSetupMessage != nil || appState.isAuthorizing)
            if appState.oauthSetupMessage != nil {
                Text("Google OAuth setup required")
            }
        }

        Divider()

        Button("Refresh") {
            appState.refreshMailNow()
        }
        .disabled(!appState.canRequestManualRefresh)

        Divider()

        if #available(macOS 14.0, *) {
            SettingsLink {
                Text("Settings…")
            }
        } else {
            Button("Settings…") { Self.openSettingsLegacy() }
        }

        Button("Quit Mailbell") { appState.quit() }
    }

    /// Fallback for macOS 13, where `SettingsLink` is unavailable.
    private static func openSettingsLegacy() {
        SettingsWindow.open()
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
}

struct SettingsView: View {
    @ObservedObject var appState: AppState
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginItemStatus = LoginItem.status
    @AppStorage(AppPreferenceKeys.showMenuBarIcon) private var showMenuBarIcon = AppPreferences.defaultShowMenuBarIcon

    var body: some View {
        Form {
            notificationSection
            startupSection
            accountsSection
        }
        .formStyle(.grouped)
        .frame(width: 660)
        .frame(minHeight: 560)
        .onAppear {
            // Accessory apps have no Dock icon; make sure the window comes forward.
            refreshBehaviorState()
            NSApp.activate(ignoringOtherApps: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NSApp.keyWindow?.makeFirstResponder(nil)
            }
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
                .foregroundStyle(appState.notificationAuthorizationState.canPostAlert ? .green : .secondary)
            }

            Text(appState.notificationAuthorizationState.detail)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            ControlGroup {
                Button("Refresh Gmail") {
                    appState.refreshMailNow()
                }
                .disabled(!appState.canRequestManualRefresh)

                Button("Refresh notification status") {
                    appState.refreshNotificationAuthorizationState()
                }

                Button("Test notification") {
                    appState.sendTestNotification()
                }

                if appState.notificationAuthorizationState.canRequestPermission {
                    Button("Request Permission") {
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
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let message = appState.notificationTestMessage {
                Label(message, systemImage: "bell.badge")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .task {
            appState.refreshNotificationAuthorizationState()
        }
    }

    private var startupSection: some View {
        Section("Startup") {
            Toggle("Start at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { newValue in
                    LoginItem.set(newValue)
                    refreshLoginItemStatus()
                }

            Toggle("Show menu bar icon", isOn: $showMenuBarIcon)
                .onChange(of: showMenuBarIcon) { newValue in
                    AppPreferences.setShowMenuBarIcon(newValue)
                }

            LabeledContent("Login item") {
                Label(
                    loginItemStatus.title,
                    systemImage: loginItemStatus == .enabled ? "checkmark.circle.fill" : "info.circle"
                )
                .foregroundStyle(loginItemStatus == .enabled ? .green : .secondary)
            }

            Text(loginItemStatus.detail)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            if loginItemStatus == .requiresApproval || loginItemStatus == .unavailable {
                Button("Open System Settings") {
                    SystemSettings.open()
                }
            }

            Text("If you hide the menu bar icon, Mailbell keeps running. Relaunch Mailbell to reopen Settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
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
            .buttonStyle(.borderedProminent)
            .disabled(appState.oauthSetupMessage != nil || appState.isAuthorizing)
            .help(appState.isAuthorizing ? "Complete Google sign-in in your browser." : "Add a Gmail account.")

            if appState.accounts.isEmpty {
                Label("No accounts connected", systemImage: "person.crop.circle.badge.exclamationmark")
                Text(accountEmptyDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(appState.accounts.enumerated()), id: \.element.id) { index, accountState in
                    if index > 0 {
                        Divider()
                    }
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
                    .buttonStyle(.bordered)

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
            .font(.caption)
            .foregroundStyle(.orange)
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
