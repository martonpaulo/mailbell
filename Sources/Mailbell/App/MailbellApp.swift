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
            Button(appState.isAuthorizing ? "Authorizing..." : "Add Google Account") {
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
            return "\(connected) accounts connected"
        }
        if connected > 0 {
            return "\(connected) of \(enabled.count) connected"
        }
        return "\(enabled.count) accounts enabled"
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
                    Label("Behavior", systemImage: "gearshape")
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

            Label(loginItemStatus.title, systemImage: loginItemStatus == .enabled ? "checkmark.circle.fill" : "info.circle")
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

                Button("Add Google Account") {
                    appState.addGoogleAccount()
                }
                .buttonStyle(.borderedProminent)
                .disabled(appState.oauthSetupMessage != nil || appState.isAuthorizing)
                .help(appState.isAuthorizing ? "Complete Google sign-in in your browser." : "Add a Gmail account.")
            }

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
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
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
            GridRow {
                Color.clear
                    .frame(width: SettingsFormMetrics.labelWidth)
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var accountEmptyDetail: String {
        if appState.oauthSetupMessage != nil {
            return "Set up your local Google OAuth credentials before adding an account."
        }
        if appState.isAuthorizing {
            return "Complete Google sign-in in your browser."
        }
        return "Add a Google account to start watching Gmail Inbox."
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
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
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

private struct OAuthSetupPanel: View {
    let details: String
    @State private var showsDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Google OAuth setup required", systemImage: "key.fill")
                .font(.headline)
                .foregroundStyle(.orange)

            Text("Create your own Google Desktop OAuth client, set `MAILBELL_GOOGLE_CLIENT_ID` and `MAILBELL_GOOGLE_CLIENT_SECRET`, then rebuild or reinstall Mailbell.")
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                if let readmeURL = SetupGuide.readmeURL {
                    Button("Open README") {
                        NSWorkspace.shared.open(readmeURL)
                    }
                }
                Text("See README > Google Cloud Setup.")
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            DisclosureGroup("Details", isExpanded: $showsDetails) {
                Text(details)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }
}

private enum SetupGuide {
    static var readmeURL: URL? {
        var candidates = [
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("README.md"),
            Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("README.md")
        ]
        if let bundledURL = Bundle.main.url(forResource: "README", withExtension: "md") {
            candidates.append(bundledURL)
        }

        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }
}

private enum SystemSettings {
    static func open() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }
}

enum SettingsFormMetrics {
    static let labelWidth: CGFloat = 104
}

struct SettingsFieldRow<Content: View>: View {
    private let title: String
    private let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        GridRow {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: SettingsFormMetrics.labelWidth, alignment: .trailing)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
