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

    private var noAccountSection: some View {
        Group {
            Text("Not connected")
            if let setupMessage = appState.oauthSetupMessage {
                Text("Google OAuth setup required")
                Text(setupMessage)
            }
            Button(appState.isAuthorizing ? "Authorizing…" : "Add Gmail Account") {
                appState.addGoogleAccount()
            }
            .disabled(appState.oauthSetupMessage != nil || appState.isAuthorizing)
        }
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
            }
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

// swiftlint:disable:next type_body_length
struct SettingsView: View {
    @ObservedObject var appState: AppState
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginItemStatus = LoginItem.status
    @State private var webmailBrowsers: [BrowserCandidate] = []
    @State private var chromeProfiles: [ChromeProfileCandidate] = []
    @State private var didLoadWebmailOptions = false
    @State private var accountPendingRemoval: MailAccount?

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
        .confirmationDialog(
            accountRemovalTitle,
            isPresented: accountRemovalBinding,
            titleVisibility: .visible
        ) {
            Button("Remove Account", role: .destructive) {
                if let account = accountPendingRemoval {
                    appState.removeAccount(accountID: account.id)
                    accountPendingRemoval = nil
                }
            }
            Button("Cancel", role: .cancel) {
                accountPendingRemoval = nil
            }
        } message: {
            Text(
                "Mailbell will delete local tokens and stop notifications for this account. "
                    + "Gmail mail will not be changed."
            )
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
        .task {
            await loadWebmailOptionsIfNeeded()
        }
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
                notificationPermissionStatus
            }

            LabeledContent("Alerts") {
                notificationSettingStatusValue(appState.notificationAuthorizationState.alertSetting, context: "Alerts")
            }

            LabeledContent("Sound") {
                notificationSettingStatusValue(appState.notificationAuthorizationState.soundSetting, context: "Sound")
            }

            LabeledContent("Badge") {
                notificationSettingStatusValue(appState.notificationAuthorizationState.badgeSetting, context: "Badge")
            }
        } header: {
            Text("Notifications")
        } footer: {
            settingsFooter(notificationFooterText)
        }
    }

    private var notificationActionsSection: some View {
        Section {
            LabeledContent("Notification Status") {
                Button("Refresh") {
                    appState.refreshNotificationAuthorizationState(showStatusMessage: true)
                }
            }

            LabeledContent("Test Notification") {
                if appState.isSendingTestNotification {
                    SettingsProgressValue("Sending", context: "Test notification")
                } else {
                    Button("Send") {
                        appState.sendTestNotification()
                    }
                }
            }

            if appState.notificationAuthorizationState.canRequestPermission {
                LabeledContent("Permission Request") {
                    Button("Request") {
                        appState.requestNotificationAuthorization()
                    }
                }
            }

            if appState.notificationAuthorizationState.shouldOpenSystemSettings {
                LabeledContent("System Settings") {
                    Button("Open") {
                        SystemSettings.open()
                    }
                }
            }
        } header: {
            Text("Notification Controls")
        } footer: {
            notificationActionsFooter
        }
    }

    private var pendingCountSection: some View {
        Section {
            Toggle(
                "Show review count",
                isOn: Binding(
                    get: { appState.showPendingCount },
                    set: { appState.setShowPendingCount($0) }
                )
            )
        } header: {
            Text("Menu Bar")
        } footer: {
            settingsFooter(
                "Shows the number of messages awaiting review in the menu bar."
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
                loginItemStatusValue
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
                    SettingsStatusValue("Required", tone: .warning, context: "Setup")
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
                    SettingsStatusValue("No account connected", tone: .inactive, context: "Accounts")
                }
            }

            LabeledContent("New Account") {
                addAccountButton(title: "Add Account")
            }

            LabeledContent("Check Mail") {
                Button("Check Now") {
                    appState.refreshMailNow()
                }
                .disabled(!appState.canRequestManualRefresh)
                .help(refreshHelpText)
            }
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
            accountIdentityRows

            Toggle(
                accountEnabledTitle(for: state),
                isOn: Binding(
                    get: { state.account.isEnabled },
                    set: { appState.setAccountEnabled($0, accountID: state.account.id) }
                )
            )

            LabeledContent("Status") {
                accountStatusValue(for: state)
            }

            if appState.showPendingCount {
                LabeledContent(PendingCopy.reviewSectionTitle) {
                    Text(PendingCopy.reviewCountText(pendingCount(accountID: state.account.id)))
                }
            }

            LabeledContent("Open in Browser") {
                Button("Open") {
                    appState.openGmail(accountID: state.account.id)
                }
            }

            accountActionRow(for: state)

            LabeledContent("Remove Account") {
                Button("Remove", role: .destructive) {
                    accountPendingRemoval = state.account
                }
                .foregroundStyle(.red)
            }
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
                "When enabled, unread Spam can appear in alerts and the review count. "
                    + "When disabled, Mailbell ignores Spam and removes existing Spam messages awaiting review."
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
                        accountState: state,
                        browsers: webmailBrowsers,
                        chromeProfiles: chromeProfiles
                    )
                } header: {
                    Text("Gmail Opening")
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
                LabeledContent("Setup Guide") {
                    Button("Open") {
                        NSWorkspace.shared.open(readmeURL)
                    }
                }
            }
        } header: {
            Text("Support")
        } footer: {
            settingsFooter("The setup guide explains local OAuth credentials, IMAP access, and troubleshooting.")
        }
    }

    private var accountIdentityRows: some View {
        Group {
            LabeledContent("Type") {
                Text("Gmail Account")
            }
        }
    }

    private var accountRemovalTitle: String {
        guard let accountPendingRemoval else { return "Remove Account?" }
        return "Remove \(accountPendingRemoval.email)?"
    }

    private var accountRemovalBinding: Binding<Bool> {
        Binding(
            get: { accountPendingRemoval != nil },
            set: { isPresented in
                if !isPresented {
                    accountPendingRemoval = nil
                }
            }
        )
    }

    private func accountEnabledTitle(for state: AccountRuntimeState) -> String {
        state.account.isEnabled ? "Disable Account" : "Enable Account"
    }

    @ViewBuilder
    private func accountActionRow(for state: AccountRuntimeState) -> some View {
        if let action = AccountRecoveryAction.needed(for: state), action == .signInAgain {
            LabeledContent(action.title) {
                Button(appState.isAuthorizing ? "Authorizing…" : action.title) {
                    appState.reauthenticate(accountID: state.account.id)
                }
                .disabled(appState.isAuthorizing)
            }
        } else {
            LabeledContent("Reconnect") {
                Button("Reconnect") {
                    appState.reconnect(accountID: state.account.id)
                }
                .disabled(!state.account.isEnabled || appState.isAuthorizing)
            }
        }
    }

    private func addAccountButton(title: String) -> some View {
        Button(appState.isAuthorizing ? "Authorizing…" : title) {
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

    private var notificationPermissionStatus: SettingsStatusValue {
        let state = appState.notificationAuthorizationState
        guard state.isBundled else {
            return SettingsStatusValue(state.summary, tone: .warning, context: "Notification permission")
        }

        switch state.status {
        case .authorized, .provisional, .ephemeral:
            return SettingsStatusValue(state.summary, tone: .success, context: "Notification permission")
        case .denied:
            return SettingsStatusValue(state.summary, tone: .error, context: "Notification permission")
        case .notDetermined:
            return SettingsStatusValue(state.summary, tone: .warning, context: "Notification permission")
        @unknown default:
            return SettingsStatusValue(state.summary, tone: .warning, context: "Notification permission")
        }
    }

    private func notificationSettingStatusValue(
        _ setting: UNNotificationSetting,
        context: String
    ) -> SettingsStatusValue {
        switch setting {
        case .enabled:
            return SettingsStatusValue("Enabled", tone: .success, context: context)
        case .disabled:
            return SettingsStatusValue("Disabled", tone: .inactive, context: context)
        case .notSupported:
            return SettingsStatusValue("Not supported", tone: .inactive, context: context)
        @unknown default:
            return SettingsStatusValue("Unavailable", tone: .warning, context: context)
        }
    }

    private var loginItemStatusValue: SettingsStatusValue {
        switch loginItemStatus {
        case .enabled:
            SettingsStatusValue(loginItemStatus.title, tone: .success, context: "Login item")
        case .disabled:
            SettingsStatusValue(loginItemStatus.title, tone: .inactive, context: "Login item")
        case .requiresApproval, .unavailable:
            SettingsStatusValue(loginItemStatus.title, tone: .warning, context: "Login item")
        }
    }

    @ViewBuilder
    private func accountStatusValue(for state: AccountRuntimeState) -> some View {
        let title = AccountPresentation.statusText(for: state)
        if !state.account.isEnabled {
            SettingsStatusValue(title, tone: .inactive, context: "Account status")
        } else {
            switch state.status {
            case .connected:
                SettingsStatusValue(title, tone: .success, context: "Account status")
            case .connecting, .reconnecting:
                SettingsProgressValue(title, context: "Account status")
            case .signedOut:
                SettingsStatusValue(title, tone: .inactive, context: "Account status")
            case .reauthRequired, .error:
                SettingsStatusValue(title, tone: .error, context: "Account status")
            }
        }
    }

    @ViewBuilder
    private var notificationActionsFooter: some View {
        if appState.isSendingTestNotification {
            settingsFooter("Sending test notification…")
        } else {
            settingsFooter(notificationActionsFooterText)
        }
    }

    private var notificationActionsFooterText: String {
        if let message = appState.notificationTestMessage {
            return message
        }
        if let message = appState.notificationStatusMessage {
            return message
        }
        return "Use Refresh after changing notification settings in macOS."
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
            return "Checks Gmail for unread messages and updates the review count."
        }
        return "Enable an account to check Gmail."
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
            "Choose the browser or Chrome profile already signed in to this Gmail account."
        ]
        if let error = state.webmailOpenError {
            lines.append(error)
        }
        return lines.joined(separator: "\n")
    }

    private func accountDetailText(for state: AccountRuntimeState) -> String {
        AccountPresentation.detailText(for: state, includeSpam: appState.includeSpam)
    }

    private var notificationFooterText: String {
        guard notificationNeedsAttention else {
            return "Mailbell uses macOS notification settings for alerts, sound, and badge."
        }
        return appState.notificationAuthorizationState.detail
    }

    private var notificationNeedsAttention: Bool {
        !appState.notificationAuthorizationState.canPostAlert
    }

    private func refreshBehaviorState() {
        appState.refreshNotificationAuthorizationState()
        refreshLoginItemStatus()
    }

    @MainActor
    private func loadWebmailOptionsIfNeeded() async {
        guard !didLoadWebmailOptions else { return }
        didLoadWebmailOptions = true
        webmailBrowsers = BrowserRegistry.browsers()
        chromeProfiles = await ChromeProfileStore.loadProfilesAsync()
    }

    private func refreshLoginItemStatus() {
        loginItemStatus = LoginItem.status
        launchAtLogin = loginItemStatus == .enabled || loginItemStatus == .requiresApproval
    }

    private func pendingCount(accountID: UUID) -> Int {
        appState.pendingCount(accountID: accountID)
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
