import AppKit
import SwiftUI
import UserNotifications

@main
struct MailbellApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()

    @SceneBuilder
    var body: some Scene {
        MenuBarExtra {
            MenuContent(appState: appState)
        } label: {
            MenuBarLabel(
                systemImage: appState.menuBarIconSystemImage,
                pendingCount: appState.emailStoreItems.count,
                showsPendingCount: appState.showPendingCount,
                needsAttention: appState.needsAttention
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
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        true
    }
}

private struct MenuBarLabel: View {
    let systemImage: String
    let pendingCount: Int
    let showsPendingCount: Bool
    let needsAttention: Bool

    var body: some View {
        HStack(spacing: Token.Size.menuBarCountSpacing) {
            Image(systemName: systemImage)
            if !needsAttention, showsPendingCount, pendingCount > 0 {
                Text("\(pendingCount)")
                    .monospacedDigit()
            }
        }
        .accessibilityLabel(
            PendingCopy.menuBarAccessibilityLabel(
                count: pendingCount,
                showsCount: showsPendingCount,
                needsAttention: needsAttention
            )
        )
    }
}

struct MenuContent: View {
    @Environment(\.openSettings) private var openSettings
    @ObservedObject var appState: AppState

    var body: some View {
        if appState.accounts.isEmpty {
            noAccountSection
        } else {
            accountsMenuSection
        }

        Divider()

        emailStoreSection

        Divider()

        Button {
            appState.refreshMailNow()
        } label: { Text("Check Now") }
            .disabled(!appState.canRequestManualRefresh)

        Divider()

        Button {
            SettingsWindowPresenter.bringToFront()
            openSettings()
            SettingsWindowPresenter.bringToFront()
        } label: {
            Text("Settings…")
        }

        Button {
            appState.quit()
        } label: {
            Text("Quit Mailbell")
        }
    }

    @ViewBuilder
    private var noAccountSection: some View {
        Text("Not connected")
        if let setupMessage = appState.oauthSetupMessage {
            Text("This build is missing its Google OAuth configuration")
            Text(setupMessage)
        }
        Button(appState.isAuthorizing ? "Authorizing…" : "Add Gmail Account") {
            appState.addGoogleAccount()
        }
        .disabled(appState.oauthSetupMessage != nil || appState.isAuthorizing)
    }

    private var accountsMenuSection: some View {
        Section("Accounts") {
            ForEach(appState.accounts) { accountState in
                Menu {
                    if let reviewCount = reviewMenuCount(accountID: accountState.account.id) {
                        Text(PendingCopy.reviewCountText(reviewCount))
                    }
                    Button("Open Gmail") {
                        appState.openGmail(accountID: accountState.account.id)
                    }
                    if let action = AccountRecoveryAction.needed(for: accountState) {
                        Button(action.title) {
                            perform(action, accountID: accountState.account.id)
                        }
                        .disabled(actionDisabled(action))
                    }
                } label: {
                    Label(
                        AccountPresentation.menuTitle(for: accountState),
                        systemImage: AccountPresentation.menuIconSystemName(for: accountState)
                    )
                }
            }
        }
    }

    private var emailStoreSection: some View {
        Section(PendingCopy.menuSectionTitle) {
            if appState.emailStoreItems.isEmpty {
                Text(PendingCopy.emptyMenuTitle)
            } else {
                ForEach(appState.emailStoreItems) { email in
                    let sender = EmailHeaderFormatter.senderIdentity(from: email.sender)
                    Menu {
                        Label(sender.name, systemImage: "person.crop.circle")
                        if let address = sender.address, address != sender.name {
                            Label(address, systemImage: "at")
                        }
                        Label(email.time, systemImage: "clock")
                        if !email.bodyPreviewLines.isEmpty {
                            Divider()
                            ForEach(Array(email.bodyPreviewLines.enumerated()), id: \.offset) { index, line in
                                if index == 0 {
                                    Label(line, systemImage: "text.quote")
                                } else {
                                    Text(line)
                                }
                            }
                        }
                        Divider()
                        Button(PendingCopy.openActionTitle) {
                            appState.openEmail(id: email.id)
                        }
                        Button(PendingCopy.markAsReadActionTitle) {
                            appState.markEmailAsRead(id: email.id)
                        }
                        .disabled(!email.canMarkAsRead)
                        Button {
                            appState.dismissEmail(id: email.id)
                        } label: {
                            Text(PendingCopy.dismissActionTitle)
                        }
                    } label: {
                        Label(email.title, systemImage: "envelope")
                    }
                }

                bulkActionsSection
            }
        }
    }

    /// Bulk actions are grouped in their own submenu, so destructive
    /// whole-queue commands are never sitting loose beside per-message ones.
    private var bulkActionsSection: some View {
        Menu {
            Button {
                appState.markAllEmailsAsRead()
            } label: {
                Text(
                    appState.isMarkingAllAsRead
                        ? PendingCopy.markingAllAsReadActionTitle
                        : PendingCopy.markAllAsReadActionTitle
                )
            }
            .disabled(!appState.canMarkAllAsRead)

            Button {
                appState.dismissAllEmails()
            } label: {
                Text(PendingCopy.dismissAllActionTitle)
            }
            .disabled(appState.isMarkingAllAsRead)
        } label: {
            Label(PendingCopy.bulkActionsMenuTitle, systemImage: "tray.full")
        }
    }

    private func pendingCount(accountID: UUID) -> Int {
        appState.pendingCount(accountID: accountID)
    }

    private func reviewMenuCount(accountID: UUID) -> Int? {
        appState.showPendingCount ? pendingCount(accountID: accountID) : nil
    }

    private func perform(_ action: AccountRecoveryAction, accountID: UUID) {
        switch action {
        case .enable:
            appState.setAccountEnabled(true, accountID: accountID)
        case .reconnect:
            appState.reconnect(accountID: accountID)
        case .signInAgain:
            appState.reauthenticate(accountID: accountID)
        }
    }

    private func actionDisabled(_ action: AccountRecoveryAction) -> Bool {
        action.requiresAuthorizationSlot && appState.isAuthorizing
    }
}
