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

enum SettingsTab: CaseIterable, Identifiable {
    case general
    case notifications
    case accounts
    case advanced
    case about

    var id: Self { self }

    var title: String {
        switch self {
        case .general:
            "General"
        case .notifications:
            "Notifications"
        case .accounts:
            "Accounts"
        case .advanced:
            "Advanced"
        case .about:
            "About"
        }
    }

    var systemImage: String {
        switch self {
        case .general:
            "gearshape"
        case .notifications:
            "bell"
        case .accounts:
            "person.crop.circle"
        case .advanced:
            "slider.horizontal.3"
        case .about:
            "info.circle"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var appState: AppState
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginItemStatus = LoginItem.status

    var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label(SettingsTab.general.title, systemImage: SettingsTab.general.systemImage)
                }

            notificationsTab
                .tabItem {
                    Label(SettingsTab.notifications.title, systemImage: SettingsTab.notifications.systemImage)
                }

            accountsTab
                .tabItem {
                    Label(SettingsTab.accounts.title, systemImage: SettingsTab.accounts.systemImage)
                }

            advancedTab
                .tabItem {
                    Label(SettingsTab.advanced.title, systemImage: SettingsTab.advanced.systemImage)
                }

            aboutTab
                .tabItem {
                    Label(SettingsTab.about.title, systemImage: SettingsTab.about.systemImage)
                }
        }
        .onAppear {
            refreshBehaviorState()
        }
    }

    private var generalTab: some View {
        Form {
            pendingCountSection
            startupSection
        }
        .formStyle(.grouped)
    }

    private var notificationsTab: some View {
        Form {
            notificationStatusSection
            notificationActionsSection
        }
        .formStyle(.grouped)
    }

    private var accountsTab: some View {
        Form {
            accountOverviewSection
            accountSections
        }
        .formStyle(.grouped)
    }

    private var advancedTab: some View {
        Form {
            spamSection
            webmailSections
            oauthSetupSection
        }
        .formStyle(.grouped)
    }

    private var aboutTab: some View {
        Form {
            aboutAppSection
            aboutSupportSection
        }
        .formStyle(.grouped)
    }

    private var notificationStatusSection: some View {
        Section {
            LabeledContent("Permission") {
                Label(
                    appState.notificationAuthorizationState.summary,
                    systemImage: appState.notificationAuthorizationState.canPostAlert
                        ? "bell.badge.fill"
                        : "bell.slash"
                )
            }

            LabeledContent("Alerts") {
                Text(notificationSettingStatus(setting: appState.notificationAuthorizationState.alertSetting))
            }

            LabeledContent("Sound") {
                Text(notificationSettingStatus(setting: appState.notificationAuthorizationState.soundSetting))
            }

            LabeledContent("Badge") {
                Text(notificationSettingStatus(setting: appState.notificationAuthorizationState.badgeSetting))
            }
        } header: {
            Text("Notifications")
        } footer: {
            settingsFooter(notificationFooterText)
        }
    }

    private var notificationActionsSection: some View {
        Section {
            Button("Refresh Status") {
                appState.refreshNotificationAuthorizationState()
            }

            Button("Send Test Notification") {
                appState.sendTestNotification()
            }
            .disabled(appState.isSendingTestNotification)

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
        } header: {
            Text("Actions")
        } footer: {
            notificationActionsFooter
        }
    }

    private var pendingCountSection: some View {
        Section {
            Toggle(
                "Show pending count",
                isOn: Binding(
                    get: { appState.showPendingCount },
                    set: { appState.setShowPendingCount($0) }
                )
            )
        } header: {
            Text("Menu Bar")
        } footer: {
            settingsFooter(
                "Shows the number of pending emails in the menu bar when there is something to review."
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
    private var accountOverviewSection: some View {
        Section {
            if let setupMessage = appState.oauthSetupMessage {
                LabeledContent("Setup") {
                    Text("Required")
                }
                DisclosureGroup("Setup Details") {
                    Text(setupMessage)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            if appState.hasAccounts {
                LabeledContent("Accounts") {
                    Text(accountCountText)
                }
            } else {
                LabeledContent("Status") {
                    Text("No account connected")
                }
            }

            addAccountButton(title: appState.hasAccounts ? "Add Another Gmail Account" : "Add Gmail Account")

            Button("Refresh Gmail") {
                appState.refreshMailNow()
            }
            .disabled(!appState.canRequestManualRefresh)
            .help(refreshHelpText)
        } header: {
            Text("Gmail")
        } footer: {
            settingsFooter(accountOverviewFooterText)
        }
    }

    @ViewBuilder
    private var accountSections: some View {
        ForEach(appState.accounts) { state in
            accountSection(for: state)
        }
    }

    private func accountSection(for state: AccountRuntimeState) -> some View {
        Section {
            accountIdentityRows(for: state)

            if appState.showPendingCount {
                LabeledContent(PendingCopy.menuSectionTitle) {
                    Text(PendingCopy.countText(pendingCount(accountID: state.account.id)))
                }
            }

            Toggle(
                "Enable account",
                isOn: Binding(
                    get: { state.account.isEnabled },
                    set: { appState.setAccountEnabled($0, accountID: state.account.id) }
                )
            )

            Button("Open Gmail") {
                appState.openGmail(accountID: state.account.id)
            }

            AccountActionsMenu(appState: appState, accountState: state)
        } header: {
            Text(state.account.email)
        } footer: {
            settingsFooter(accountFooterText(for: state))
        }
    }

    private var spamSection: some View {
        Section {
            Toggle(
                "Include spam",
                isOn: Binding(
                    get: { appState.includeSpam },
                    set: { appState.setIncludeSpam($0) }
                )
            )
        } header: {
            Text("Spam")
        } footer: {
            settingsFooter(
                "When enabled, unread Spam can appear in alerts and the pending count. "
                    + "When disabled, Mailbell ignores Spam and removes existing spam pending items."
            )
        }
    }

    @ViewBuilder
    private var webmailSections: some View {
        if appState.accounts.isEmpty {
            Section {
                LabeledContent("Open with") {
                    Text("Add a Gmail account")
                }
            } header: {
                Text("Webmail")
            } footer: {
                settingsFooter("Webmail routing is configured per Gmail account.")
            }
        } else {
            ForEach(appState.accounts) { state in
                Section {
                    AccountWebmailSettingsView(
                        appState: appState,
                        accountState: state
                    )
                } header: {
                    Text("Open \(state.account.email)")
                } footer: {
                    settingsFooter(webmailFooterText(for: state))
                }
            }
        }
    }

    @ViewBuilder
    private var oauthSetupSection: some View {
        if let setupMessage = appState.oauthSetupMessage {
            Section {
                OAuthSetupPanel(details: setupMessage)
            } header: {
                Text("Google OAuth Setup")
            } footer: {
                settingsFooter("Mailbell uses your local Google Desktop OAuth client for Gmail IMAP access.")
            }
        }
    }

    private var aboutAppSection: some View {
        Section {
            LabeledContent("App") {
                Text("Mailbell")
            }

            LabeledContent("Version") {
                Text(appVersionText)
            }

            LabeledContent("Bundle ID") {
                Text(AppIdentity.bundleIdentifier)
                    .textSelection(.enabled)
            }
        } header: {
            Text("About")
        } footer: {
            settingsFooter("Mailbell is a local macOS menu bar notifier for Gmail.")
        }
    }

    private var aboutSupportSection: some View {
        Section {
            if let readmeURL = SetupGuide.readmeURL {
                Button("Open Setup Guide") {
                    NSWorkspace.shared.open(readmeURL)
                }
            }
        } header: {
            Text("Support")
        } footer: {
            settingsFooter("The setup guide explains local OAuth credentials, IMAP access, and troubleshooting.")
        }
    }

    private func accountIdentityRows(for state: AccountRuntimeState) -> some View {
        Group {
            LabeledContent("Email") {
                Text(state.account.email)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }

            LabeledContent("Status") {
                Text(AccountPresentation.statusText(for: state))
            }
        }
    }

    private func addAccountButton(title: String) -> some View {
        Button(appState.isAuthorizing ? "Authorizing..." : title) {
            appState.addGoogleAccount()
        }
        .disabled(appState.oauthSetupMessage != nil || appState.isAuthorizing)
        .help(appState.isAuthorizing ? "Complete Google sign-in in your browser." : "Add a Gmail account.")
    }

    private func settingsFooter(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
    }

    @ViewBuilder
    private var notificationActionsFooter: some View {
        if appState.isSendingTestNotification {
            ProgressView("Sending test notification...")
        } else {
            settingsFooter(notificationActionsFooterText)
        }
    }

    private var notificationActionsFooterText: String {
        if let message = appState.notificationTestMessage {
            return message
        }
        return "Use Refresh Status after changing notification settings in macOS."
    }

    private var accountCountText: String {
        "\(appState.accounts.count) \(appState.accounts.count == 1 ? "account" : "accounts")"
    }

    private var accountOverviewFooterText: String {
        var lines = [refreshHelpText]
        if let message = appState.manualRefreshMessage {
            lines = [message]
        }
        if let error = appState.lastError {
            lines.append(error)
        }
        return lines.joined(separator: "\n")
    }

    private var refreshHelpText: String {
        if appState.isAuthorizing {
            return "Complete Google sign-in in your browser."
        }
        if appState.canRequestManualRefresh {
            return "Refresh Gmail requests a reconnect and reconciles pending mail with Gmail unread state."
        }
        return "Enable a Gmail account before refreshing."
    }

    private func accountFooterText(for state: AccountRuntimeState) -> String {
        var lines = [accountDetailText(for: state)]
        if let error = state.lastError {
            lines.append(error)
        }
        return lines.joined(separator: "\n")
    }

    private func webmailFooterText(for state: AccountRuntimeState) -> String {
        var lines = [
            "Choose the browser or Chrome profile already signed in to \(state.account.email)."
        ]
        if let error = state.webmailOpenError {
            lines.append(error)
        }
        return lines.joined(separator: "\n")
    }

    private func accountDetailText(for state: AccountRuntimeState) -> String {
        "\(state.account.providerID.displayName) · \(AccountPresentation.detailText(for: state))"
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

    private func notificationSettingStatus(setting: UNNotificationSetting) -> String {
        switch setting {
        case .enabled:
            "Enabled"
        case .disabled:
            "Disabled"
        case .notSupported:
            "Not supported"
        @unknown default:
            "Unavailable"
        }
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

    private var appVersionText: String {
        let info = Bundle.main.infoDictionary
        let version = (info?["CFBundleShortVersionString"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let build = (info?["CFBundleVersion"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let displayVersion = version?.isEmpty == false ? version! : "Development"
        guard let build, !build.isEmpty, build != displayVersion else {
            return displayVersion
        }
        return "\(displayVersion) (\(build))"
    }
}
