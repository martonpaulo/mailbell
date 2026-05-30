import SwiftUI
import AppKit

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
    func applicationDidFinishLaunching(_ notification: Notification) {
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

        switch appState.status {
        case .needsConfig:
            Text("Open Settings to add your Google client")
        case .signedOut:
            Button("Sign in with Google") { appState.signIn() }
        case .reauthRequired:
            Button("Reconnect (sign in again)") { appState.signIn() }
        default:
            Button("Reconnect") { appState.reconnect() }
        }

        if appState.isSignedIn {
            Button("Disconnect") { appState.disconnect() }
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

    var body: some View {
        Form {
            Section("Account") {
                LabeledContent("Status", value: appState.status.menuLabel)
                LabeledContent("Account", value: appState.accountEmail ?? "Not connected")
                if let error = appState.lastError {
                    LabeledContent("Last error", value: error)
                }
            }

            Section("Google OAuth client") {
                TextField("Client ID", text: $clientID, prompt: Text("…apps.googleusercontent.com"))
                SecureField("Client secret", text: $clientSecret, prompt: Text("Desktop client secret"))
                Button("Save client") {
                    appState.saveConfig(clientID: clientID, clientSecret: clientSecret)
                }
                .disabled(clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Text("Create a Desktop-app OAuth client in Google Cloud Console. See README.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Behavior") {
                Toggle("Start at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { newValue in
                        LoginItem.set(newValue)
                    }
            }

            Section {
                if appState.isSignedIn {
                    Button("Disconnect") { appState.disconnect() }
                } else {
                    Button("Sign in with Google") { appState.signIn() }
                        .disabled(!appState.isConfigured)
                }
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear {
            // Accessory apps have no Dock icon; make sure the window comes forward.
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
