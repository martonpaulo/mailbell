import AppKit
import MailbellKit
import SwiftUI
import UserNotifications

@main
struct MailbellApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appState = AppState()

    init() {
        LegacyDomainMigration.runOnLaunch()
    }

    @SceneBuilder
    var body: some Scene {
        MenuBarExtra {
            MenuContent(appState: appState)
        } label: {
            MenuBarLabel(
                systemImage: appState.menuBarIconSystemImage,
                shownConversationCount: appState.shownItems.count,
                showsMenuBarCount: appState.showsMenuBarCount,
                needsAttention: appState.needsAttention,
                needsSignIn: appState.needsSignIn
            )
        }

        Settings {
            SettingsView(appState: appState)
        }
        .defaultSize(width: Token.Size.paneWidth, height: Token.Size.paneHeight)
        .windowResizability(.contentMinSize)
    }
}

/// Keeps the app out of the Dock and app switcher (accessory style).
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_: Notification) {
        NSApp.setActivationPolicy(.accessory)
        guard ScreenshotMode.isEnabled else { return }
        // An accessory app has no Dock icon to click, so the window has to be
        // brought forward for capture. Ordinary launches never reach this.
        NSApp.setActivationPolicy(.regular)
        if let appearance = ScreenshotMode.requestedAppearance() {
            NSApp.appearance = NSAppearance(named: appearance)
        }
        ScreenshotMode.pinEnvironment()
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        true
    }
}

private struct MenuBarLabel: View {
    @Environment(\.openSettings) private var openSettings
    let systemImage: String
    let shownConversationCount: Int
    let showsMenuBarCount: Bool
    let needsAttention: Bool
    let needsSignIn: Bool

    var body: some View {
        HStack(spacing: Token.Size.menuBarCountSpacing) {
            Image(systemName: systemImage)
            if !needsAttention, showsMenuBarCount, shownConversationCount > 0 {
                Text("\(shownConversationCount)")
                    .monospacedDigit()
            }
        }
        .accessibilityLabel(
            MenuCopy.menuBarAccessibilityLabel(
                count: shownConversationCount,
                showsCount: showsMenuBarCount,
                needsAttention: needsAttention,
                needsSignIn: needsSignIn
            )
        )
        .task {
            openSettingsForCapture()
        }
    }
}

extension MenuBarLabel {
    /// Screenshot mode opens Settings through the same action the menu uses, so
    /// the captured window is the one users actually see.
    fileprivate func openSettingsForCapture() {
        guard ScreenshotMode.isEnabled else { return }
        openSettings()
        ScreenshotMode.prepareWhenReady()
    }
}
