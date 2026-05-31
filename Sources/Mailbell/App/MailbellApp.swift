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

        if let email = appState.accountEmail {
            Text(email)
        }

        Divider()

        Button("Open Gmail") { appState.openGmail() }

        if appState.status == .needsConfig {
            Text("Open Settings to add your Google client")
        } else if appState.status == .signedOut {
            Button("Sign in with Google") { appState.signIn() }
        } else if appState.status == .reauthRequired {
            Text("Open Settings to sign in again")
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
}

struct SettingsView: View {
    @ObservedObject var appState: AppState
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var clientID = OAuthConfig.persistedClientID ?? ""
    @State private var clientSecret = OAuthConfig.persistedClientSecret ?? ""
    @State private var didSaveClient = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            settingsHeader

            accountPanel

            oauthPanel

            settingsPanel("Behavior") {
                Toggle("Start at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { newValue in
                        LoginItem.set(newValue)
                    }
            }
        }
        .padding(24)
        .frame(width: 520)
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

    private var settingsHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: appState.status.systemImage)
                .font(.system(size: 28, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(statusTint)
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 3) {
                Text("Mailbell")
                    .font(.title2.weight(.semibold))
                Text(appState.status.menuLabel)
                    .font(.callout)
                    .foregroundStyle(statusTint)
            }

            Spacer()
        }
    }

    private var accountPanel: some View {
        settingsPanel("Account") {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(appState.accountEmail ?? "No account connected")
                        .font(.headline)
                        .textSelection(.enabled)
                    Text(accountDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                accountAction
            }

            if let error = appState.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
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

    @ViewBuilder
    private var accountAction: some View {
        if appState.isSignedIn {
            Button("Disconnect", role: .destructive) {
                appState.disconnect()
            }
        } else {
            Button("Sign in with Google") {
                appState.signIn()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!appState.isConfigured)
        }
    }

    private var accountDetail: String {
        switch appState.status {
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

    private var statusTint: Color {
        switch appState.status {
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
