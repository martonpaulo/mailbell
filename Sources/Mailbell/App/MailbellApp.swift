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
                showsPendingCount: appState.showPendingCount
            )
        }

        Settings {
            SettingsView(appState: appState)
        }
        .defaultSize(width: 740, height: 600)
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

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage)
            if showsPendingCount, pendingCount > 0 {
                Text("\(pendingCount)")
                    .monospacedDigit()
            }
        }
        .accessibilityLabel(
            PendingCopy.menuBarAccessibilityLabel(count: pendingCount, showsCount: showsPendingCount)
        )
    }
}

struct MenuContent: View {
    @ObservedObject var appState: AppState

    var body: some View {
        if appState.accounts.isEmpty {
            noAccountSection
        } else if appState.accounts.count == 1, let accountState = appState.accounts.first {
            singleAccountSection(accountState)
        } else {
            multiAccountSection
        }

        Divider()

        emailStoreSection

        Divider()

        Button {
            appState.refreshMailNow()
        } label: { Text("Refresh Gmail") }
        .disabled(!appState.canRequestManualRefresh)

        Divider()

        SettingsLink {
            Text("Settings...")
        }

        Button {
            appState.quit()
        } label: {
            Text("Quit Mailbell")
        }
    }

    private var noAccountSection: some View {
        Group {
            Text("Not connected")
            if let setupMessage = appState.oauthSetupMessage {
                Text("Google OAuth setup required")
                Text(setupMessage)
            }
            Button(appState.isAuthorizing ? "Authorizing..." : "Add Gmail Account") {
                appState.addGoogleAccount()
            }
            .disabled(appState.oauthSetupMessage != nil || appState.isAuthorizing)
        }
    }

    private func singleAccountSection(_ accountState: AccountRuntimeState) -> some View {
        Group {
            Text(AccountPresentation.compactTitle(for: accountState))
            if let action = AccountRecoveryAction.needed(for: accountState) {
                Button(action.title) {
                    perform(action, accountID: accountState.account.id)
                }
                .disabled(actionDisabled(action))
            }
            Button("Open Gmail") {
                appState.openGmail(accountID: accountState.account.id)
            }
        }
    }

    private var multiAccountSection: some View {
        Section("Accounts") {
            ForEach(appState.accounts) { accountState in
                Button {
                    appState.openGmail(accountID: accountState.account.id)
                } label: {
                    Text(
                        AccountPresentation.multiAccountMenuTitle(
                            for: accountState,
                            pendingCount: pendingMenuCount(accountID: accountState.account.id)
                        )
                    )
                }
                if let action = AccountRecoveryAction.needed(for: accountState) {
                    Button("\(action.title) - \(accountState.account.email)") {
                        perform(action, accountID: accountState.account.id)
                    }
                    .disabled(actionDisabled(action))
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
                        Divider()
                        Button("Open") {
                            appState.openEmail(id: email.id)
                        }
                        Button {
                            appState.dismissEmail(id: email.id)
                        } label: {
                            Text("Dismiss")
                        }
                    } label: {
                        Label(email.title, systemImage: "envelope")
                    }
                }
            }
        }
    }

    private func pendingCount(accountID: UUID) -> Int {
        appState.emailStoreItems.filter { $0.accountID == accountID }.count
    }

    private func pendingMenuCount(accountID: UUID) -> Int? {
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

struct SettingsView: View {
    @ObservedObject var appState: AppState
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginItemStatus = LoginItem.status

    var body: some View {
        Form {
            notificationSection
            pendingSettingsSection
            startupSection
            accountSettings
        }
        .formStyle(.grouped)
        .onAppear {
            refreshBehaviorState()
        }
    }

    private var notificationSection: some View {
        Section {
            LabeledContent("Status") {
                Label(
                    appState.notificationAuthorizationState.summary,
                    systemImage: appState.notificationAuthorizationState.canPostAlert
                        ? "bell.badge.fill"
                        : "bell.slash"
                )
            }

            LabeledContent("Actions") {
                ControlGroup {
                    Button("Refresh Status") {
                        appState.refreshNotificationAuthorizationState()
                    }

                    Button("Test") {
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
            }

            if let message = appState.notificationTestMessage {
                Label(message, systemImage: "bell.badge")
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        } header: {
            Text("Notifications")
        } footer: {
            settingsFooter(notificationFooterText)
        }
    }

    private var pendingSettingsSection: some View {
        Section {
            Toggle(
                "Show pending count",
                isOn: Binding(
                    get: { appState.showPendingCount },
                    set: { appState.setShowPendingCount($0) }
                )
            )

            Toggle(
                "Include spam",
                isOn: Binding(
                    get: { appState.includeSpam },
                    set: { appState.setIncludeSpam($0) }
                )
            )
        } header: {
            Text(PendingCopy.menuSectionTitle)
        } footer: {
            settingsFooter(
                "Shows the number of unread or not dismissed emails.\n"
                    + "When disabled, spam messages are ignored for alerts and pending count."
            )
        }
    }

    private var startupSection: some View {
        Section {
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

            if loginItemStatus == .requiresApproval || loginItemStatus == .unavailable {
                LabeledContent("System Settings") {
                    Button("Open System Settings") {
                        SystemSettings.open()
                    }
                }
            }
        } header: {
            Text("Startup")
        } footer: {
            settingsFooter(loginItemStatus.detail)
        }
    }

    @ViewBuilder
    private var accountSettings: some View {
        if appState.accounts.count <= 1 {
            singleAccountSettings
        } else {
            multiAccountOverview
            multiAccountSections
        }
    }

    private var singleAccountSettings: some View {
        Section {
            if let setupMessage = appState.oauthSetupMessage {
                OAuthSetupPanel(details: setupMessage)
            }

            if let state = appState.accounts.first {
                accountIdentityRows(for: state, includeEmail: true)
                accountControlRows(for: state, showsMultiAccountHint: false)

                LabeledContent("Accounts") {
                    addAccountButton(title: "Add Another Gmail Account")
                }
            } else {
                LabeledContent("Gmail") {
                    addAccountButton(title: "Add Gmail Account")
                }

                Label("No account connected", systemImage: "person.crop.circle.badge.exclamationmark")
            }

            if let message = appState.manualRefreshMessage {
                refreshMessageLabel(message)
            }

            if let error = appState.lastError {
                accountErrorLabel(error)
            }
        } header: {
            Text("Account")
        } footer: {
            if let state = appState.accounts.first {
                settingsFooter(accountDetailText(for: state))
            } else {
                settingsFooter(accountEmptyDetail)
            }
        }
    }

    private var multiAccountOverview: some View {
        Section {
            if let setupMessage = appState.oauthSetupMessage {
                OAuthSetupPanel(details: setupMessage)
            }

            LabeledContent("Gmail") {
                addAccountButton(title: "Add Gmail Account")
            }

            LabeledContent("Sync") {
                Button("Refresh Gmail") {
                    appState.refreshMailNow()
                }
                .disabled(!appState.canRequestManualRefresh)
            }

            if let message = appState.manualRefreshMessage {
                refreshMessageLabel(message)
            }

            if let error = appState.lastError {
                accountErrorLabel(error)
            }
        } header: {
            Text("Accounts")
        } footer: {
            settingsFooter(
                "Use a separate browser or Chrome profile per Gmail account to keep webmail opens "
                    + "on the intended account."
            )
        }
    }

    private var multiAccountSections: some View {
        ForEach(appState.accounts) { state in
            Section {
                accountIdentityRows(for: state, includeEmail: false)
                if appState.showPendingCount {
                    LabeledContent(PendingCopy.menuSectionTitle) {
                        Text(PendingCopy.countText(pendingCount(accountID: state.account.id)))
                    }
                }
                accountControlRows(for: state, showsMultiAccountHint: true)
            } header: {
                Text(state.account.email)
            } footer: {
                settingsFooter(accountDetailText(for: state))
            }
        }
    }

    @ViewBuilder
    private func accountIdentityRows(for state: AccountRuntimeState, includeEmail: Bool) -> some View {
        if includeEmail {
            LabeledContent("Email") {
                Text(state.account.email)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
        }

        LabeledContent("Status") {
            Text(AccountPresentation.statusText(for: state))
        }
    }

    @ViewBuilder
    private func accountControlRows(
        for state: AccountRuntimeState,
        showsMultiAccountHint: Bool
    ) -> some View {
        Toggle(
            "Enable account",
            isOn: Binding(
                get: { state.account.isEnabled },
                set: { appState.setAccountEnabled($0, accountID: state.account.id) }
            )
        )

        LabeledContent("Actions") {
            ControlGroup {
                Button("Open Gmail") {
                    appState.openGmail(accountID: state.account.id)
                }

                Button("Refresh Gmail") {
                    appState.refreshMailNow()
                }
                .disabled(!state.account.isEnabled || appState.isAuthorizing)

                AccountActionsMenu(appState: appState, accountState: state)
            }
        }

        AccountWebmailSettingsView(
            appState: appState,
            accountState: state,
            showsAccountIsolationHint: showsMultiAccountHint
        )

        if let error = state.lastError {
            accountErrorLabel(error)
        }
    }

    private func addAccountButton(title: String) -> some View {
        Button(appState.isAuthorizing ? "Authorizing..." : title) {
            appState.addGoogleAccount()
        }
        .disabled(appState.oauthSetupMessage != nil || appState.isAuthorizing)
        .help(appState.isAuthorizing ? "Complete Google sign-in in your browser." : "Add a Gmail account.")
    }

    private func accountErrorLabel(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .textSelection(.enabled)
    }

    private func refreshMessageLabel(_ message: String) -> some View {
        Label(message, systemImage: "arrow.clockwise")
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
    }

    private func settingsFooter(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
    }

    private func accountDetailText(for state: AccountRuntimeState) -> String {
        "\(state.account.providerID.displayName) · \(AccountPresentation.detailText(for: state))"
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

    private var notificationSettingsDetail: String {
        [
            notificationSettingStatus(label: "Alerts", setting: appState.notificationAuthorizationState.alertSetting),
            notificationSettingStatus(label: "Sound", setting: appState.notificationAuthorizationState.soundSetting)
        ].joined(separator: " · ")
    }

    private var notificationFooterText: String {
        guard notificationNeedsAttention else { return notificationSettingsDetail }
        return "\(notificationSettingsDetail)\n\(appState.notificationAuthorizationState.detail)"
    }

    private var notificationNeedsAttention: Bool {
        !appState.notificationAuthorizationState.canPostAlert
    }

    private func notificationSettingStatus(label: String, setting: UNNotificationSetting) -> String {
        switch setting {
        case .enabled:
            "\(label) enabled"
        case .disabled:
            "\(label) disabled"
        case .notSupported:
            "\(label) not supported"
        @unknown default:
            "\(label) unavailable"
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

    private func pendingCount(accountID: UUID) -> Int {
        appState.emailStoreItems.filter { $0.accountID == accountID }.count
    }
}
