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
            if appState.status == .needsConfig {
                Text("Set up Google client in Settings")
            } else {
                Button("Add Google Account") { appState.addGoogleAccount() }
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
    @State private var clientID = OAuthConfig.persistedClientID ?? ""
    @State private var clientSecret = OAuthConfig.persistedClientSecret ?? ""
    @State private var didSaveClient = false

    var body: some View {
        TabView {
            accountsPanel
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .tabItem {
                    Label("Accounts", systemImage: "person.crop.circle")
                }

            oauthPanel
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .tabItem {
                    Label("Google OAuth", systemImage: "key")
                }

            behaviorPanel
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .tabItem {
                    Label("Behavior", systemImage: "gearshape")
                }
        }
        .padding(24)
        .frame(width: 560)
        .frame(minHeight: 430)
        .onChange(of: clientID) { _ in didSaveClient = false }
        .onChange(of: clientSecret) { _ in didSaveClient = false }
        .onAppear {
            // Accessory apps have no Dock icon; make sure the window comes forward.
            NSApp.activate(ignoringOtherApps: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NSApp.keyWindow?.makeFirstResponder(nil)
            }
        }
    }

    private var behaviorPanel: some View {
        settingsPanel("Behavior") {
            Toggle("Start at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { newValue in
                    LoginItem.set(newValue)
                }
        }
    }

    private var accountsPanel: some View {
        settingsPanel("Accounts") {
            if appState.accounts.isEmpty {
                Text("No accounts connected")
                    .font(.headline)
                Text(accountEmptyDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(appState.accounts) { accountState in
                        accountRow(accountState)
                    }
                }
            }

            if let error = appState.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
            }

            HStack {
                Spacer()
                Button("Add Google Account") {
                    appState.addGoogleAccount()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!appState.isConfigured)
            }
        }
    }

    private var oauthPanel: some View {
        settingsPanel("Google OAuth client") {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                SettingsFieldRow("Client ID") {
                    TextField("…apps.googleusercontent.com", text: $clientID)
                        .textFieldStyle(.roundedBorder)
                        .textSelection(.enabled)
                }

                SettingsFieldRow("Client secret") {
                    SecureField("Desktop client secret", text: $clientSecret)
                        .textFieldStyle(.roundedBorder)
                }
            }

            HStack {
                Text("Use a Desktop OAuth client from Google Cloud.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                if didSaveClient {
                    Label("Saved", systemImage: "checkmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button("Save") {
                    appState.saveConfig(clientID: clientID, clientSecret: clientSecret)
                    didSaveClient = true
                }
                .buttonStyle(.bordered)
                .disabled(!canSaveClient)
            }
        }
    }

    private func accountRow(_ state: AccountRuntimeState) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: state.status.systemImage)
                    .foregroundStyle(statusTint(for: state.status))
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 3) {
                    Text(state.account.email)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    Text(accountDetail(for: state))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(state.account.providerID.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()

                if state.status == .reauthRequired {
                    Button("Sign in again") {
                        appState.reauthenticate(accountID: state.account.id)
                    }
                } else {
                    Button("Reconnect") {
                        appState.reconnect(accountID: state.account.id)
                    }
                    .disabled(!state.account.isEnabled)
                }

                Button(state.account.isEnabled ? "Disable" : "Enable") {
                    appState.setAccountEnabled(!state.account.isEnabled, accountID: state.account.id)
                }

                Button("Remove", role: .destructive) {
                    appState.removeAccount(accountID: state.account.id)
                }
            }

            if let error = state.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
                    .padding(.leading, 34)
            }
        }
    }

    private var accountEmptyDetail: String {
        if appState.status == .needsConfig {
            return "Add a Google OAuth client before signing in."
        }
        return "Add a Google account to start watching Gmail Inbox."
    }

    private func accountDetail(for state: AccountRuntimeState) -> String {
        guard state.account.isEnabled else { return "Disabled." }
        switch state.status {
        case .needsConfig:
            return "Add a Google OAuth client before signing in."
        case .signedOut:
            return "Ready to sign in."
        case .connecting:
            return "Connecting to Gmail."
        case .connected:
            return "Watching Gmail Inbox."
        case .reconnecting:
            return "Reconnecting to Gmail."
        case .reauthRequired:
            return "Sign in again to refresh access."
        case .error:
            return "Check the last error below."
        }
    }

    private var canSaveClient: Bool {
        let trimmedID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else { return false }
        return trimmedID != OAuthConfig.persistedClientID || clientSecret != (OAuthConfig.persistedClientSecret ?? "")
    }

    private func statusTint(for status: MonitorStatus) -> Color {
        switch status {
        case .connected:
            return .green
        case .connecting, .reconnecting:
            return .orange
        case .reauthRequired, .error:
            return .red
        case .needsConfig, .signedOut:
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
}

private struct SettingsFieldRow<Content: View>: View {
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
                .frame(width: 88, alignment: .trailing)
            content
        }
    }
}
