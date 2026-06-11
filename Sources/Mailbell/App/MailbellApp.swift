import AppKit
import SwiftUI

@main
struct MailbellApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
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
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
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

    var body: some View {
        TabView {
            accountsPanel
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .tabItem {
                    Label("Accounts", systemImage: "person.crop.circle")
                }

            behaviorPanel
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
        }
        .padding(24)
        .frame(width: 640)
        .frame(minHeight: 430)
        .onAppear {
            // Accessory apps have no Dock icon; make sure the window comes forward.
            refreshBehaviorState()
            NSApp.activate(ignoringOtherApps: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NSApp.keyWindow?.makeFirstResponder(nil)
            }
        }
    }

    private var behaviorPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            notificationPanel
            loginItemPanel
        }
    }

    private var notificationPanel: some View {
        settingsPanel("Notifications") {
            Label(
                appState.notificationAuthorizationState.summary,
                systemImage: appState.notificationAuthorizationState.canPostAlert
                    ? "bell.badge.fill"
                    : "bell.slash"
            )
            .foregroundStyle(appState.notificationAuthorizationState.canPostAlert ? .green : .secondary)
            .font(.body)

            Text(appState.notificationAuthorizationState.detail)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
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

                Button("Refresh") {
                    appState.refreshNotificationAuthorizationState()
                }
            }
        }
        .task {
            appState.refreshNotificationAuthorizationState()
        }
    }

    private var loginItemPanel: some View {
        settingsPanel("Startup") {
            Toggle("Start at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { newValue in
                    LoginItem.set(newValue)
                    refreshLoginItemStatus()
                }

            Label(
                loginItemStatus.title,
                systemImage: loginItemStatus == .enabled ? "checkmark.circle.fill" : "info.circle"
            )
                .foregroundStyle(loginItemStatus == .enabled ? .green : .secondary)

            Text(loginItemStatus.detail)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            if loginItemStatus == .requiresApproval || loginItemStatus == .unavailable {
                Button("Open System Settings") {
                    SystemSettings.open()
                }
            }
        }
    }

    private var accountsPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Accounts")
                    .font(.headline)

                Spacer()

                Button("Add Gmail Account") {
                    appState.addGoogleAccount()
                }
                .buttonStyle(.borderedProminent)
                .disabled(appState.oauthSetupMessage != nil || appState.isAuthorizing)
                .help(appState.isAuthorizing ? "Complete Google sign-in in your browser." : "Add a Gmail account.")
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    if let setupMessage = appState.oauthSetupMessage {
                        OAuthSetupPanel(details: setupMessage)
                    }

                    if appState.accounts.isEmpty {
                        Text("No accounts connected")
                            .font(.headline)
                        Text(accountEmptyDetail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(
                                    Array(appState.accounts.enumerated()),
                                    id: \.element.id
                                ) { index, accountState in
                                    if index > 0 {
                                        Divider()
                                            .padding(.vertical, 12)
                                    }
                                    accountRow(accountState)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }

                    if let error = appState.lastError {
                        accountErrorLabel(error)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    private func accountRow(_ state: AccountRuntimeState) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: state.status.systemImage)
                    .foregroundStyle(statusTint(for: state.status))
                    .frame(width: 22, height: 22, alignment: .top)

                VStack(alignment: .leading, spacing: 3) {
                    Text(state.account.email)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    Text("\(state.account.providerID.displayName) · \(accountDetail(for: state))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button("Open Gmail") {
                    appState.openGmail(accountID: state.account.id)
                }
                .buttonStyle(.bordered)
                .fixedSize()

                AccountActionsMenu(appState: appState, accountState: state)
                    .fixedSize()
            }

            AccountWebmailSettingsView(appState: appState, accountState: state)

            if let error = state.lastError {
                accountErrorLabel(error)
            }
        }
    }

    private func accountErrorLabel(_ message: String) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 0) {
            SettingsMessageRow(message: message)
        }
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

    private func statusTint(for status: MonitorStatus) -> Color {
        switch status {
        case .connected:
            return .green
        case .connecting, .reconnecting:
            return .orange
        case .reauthRequired, .error:
            return .red
        case .signedOut:
            return .secondary
        }
    }

    private func settingsPanel<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text(title)
                .font(.headline)
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
