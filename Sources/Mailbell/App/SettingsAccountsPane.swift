import AppKit
import SwiftUI
import UserNotifications

/// Everything about connected Gmail accounts: which mailboxes are watched,
/// each account's status and recovery actions, where its mail opens, and
/// removal. An account is never described half here and half somewhere else.
extension SettingsView {
    var accountOverviewSection: some View {
        Section {
            // A build with no OAuth client cannot sign in at all, so the
            // explanation belongs here, where the user is blocked, not in a
            // diagnostics pane they would have to go looking for.
            if let setupMessage = appState.oauthSetupMessage {
                OAuthSetupPanel(details: setupMessage)
            }

            SettingsRow(title: "Connected", description: signInGuidanceText) {
                connectedAccountsValue
            }

            SettingsActionRow {
                if appState.isAuthorizing {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Waiting for Google sign-in")
                }

                Button("Check for New Mail") {
                    appState.refreshMailNow()
                }
                .disabled(!appState.canRequestManualRefresh)

                Button("Add Gmail Account…") {
                    appState.addGoogleAccount()
                }
                .disabled(appState.oauthSetupMessage != nil || appState.isAuthorizing)
            }
        } header: {
            Text("Gmail")
        } footer: {
            settingsFooter(accountOverviewFooterText)
        }
    }

    /// Applies to every account, so it sits above the per-account sections
    /// rather than hiding behind an "Advanced" pane.
    var watchedMailboxesSection: some View {
        Section {
            SettingsRow(title: "Inbox") {
                SettingsStatusValue("Always watched", tone: .success, context: "Inbox")
            }

            Toggle(
                isOn: Binding(
                    get: { appState.includeSpam },
                    set: { appState.setIncludeSpam($0) }
                )
            ) {
                SettingsRowLabel(
                    title: "Also watch the Spam folder",
                    description: "Unread Spam can then reach notifications and the review count. "
                        + "Turning this off also clears any Spam already awaiting review. "
                        + "Nothing in Gmail changes either way."
                )
            }
        } header: {
            Text("Watched Mailboxes")
        }
    }

    var accountSections: some View {
        ForEach(appState.accounts) { state in
            accountSection(for: state)
        }
    }

    func accountSection(for state: AccountRuntimeState) -> some View {
        Section {
            // The label states what being on means, so it never reads inverted
            // the way an action label would.
            Toggle(
                isOn: Binding(
                    get: { state.account.isEnabled },
                    set: { appState.setAccountEnabled($0, accountID: state.account.id) }
                )
            ) {
                SettingsRowLabel(
                    title: "Watch this account for new mail",
                    description: accountDetailText(for: state)
                )
            }

            SettingsRow(title: "Status", description: state.lastError) {
                accountStatusValue(for: state)
            }

            // Always shown: hiding a status row behind a menu bar display
            // preference would make Settings lie about what is pending.
            SettingsRow(title: PendingCopy.reviewSectionTitle) {
                Text(PendingCopy.reviewCountText(pendingCount(accountID: state.account.id)))
            }

            AccountWebmailSettingsView(
                appState: appState,
                accountState: state,
                browsers: webmailBrowsers,
                chromeProfiles: chromeProfiles
            )

            accountActionRow(for: state)
        } header: {
            Text(state.account.email)
        }
    }

    var connectedAccountsValue: some View {
        Group {
            if appState.hasAccounts {
                Text(accountCountText)
            } else {
                SettingsStatusValue("No account yet", tone: .inactive, context: "Connected")
            }
        }
    }

    var accountRemovalTitle: String {
        guard let accountPendingRemoval else { return "Remove this account?" }
        return "Remove \(accountPendingRemoval.email)?"
    }

    var accountRemovalBinding: Binding<Bool> {
        Binding(
            get: { accountPendingRemoval != nil },
            set: { isPresented in
                if !isPresented {
                    accountPendingRemoval = nil
                }
            }
        )
    }

    /// One action row per account: recovery first, then the everyday action,
    /// with the destructive one last, the way System Settings orders a group.
    func accountActionRow(for state: AccountRuntimeState) -> some View {
        let needsSignIn = AccountRecoveryAction.needed(for: state) == .signInAgain
        return SettingsActionRow {
            if needsSignIn, appState.isAuthorizing {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Waiting for Google sign-in")
            }

            Button("Remove Account…", role: .destructive) {
                accountPendingRemoval = state.account
            }

            if needsSignIn {
                Button("Sign in Again…") {
                    appState.reauthenticate(accountID: state.account.id)
                }
                .disabled(appState.isAuthorizing)
            } else {
                Button("Reconnect") {
                    appState.reconnect(accountID: state.account.id)
                }
                .disabled(!state.account.isEnabled || appState.isAuthorizing)
            }

            Button("Open Gmail") {
                appState.openGmail(accountID: state.account.id)
            }
        }
    }

    @ViewBuilder
    func accountStatusValue(for state: AccountRuntimeState) -> some View {
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

    var accountCountText: String {
        "\(appState.accounts.count) \(appState.accounts.count == 1 ? "account" : "accounts")"
    }

    var accountOverviewFooterText: String {
        joined([appState.manualRefreshMessage, appState.lastError])
    }

    /// Google's unverified-app screen is the most surprising moment in setup.
    /// Saying so before the user meets it costs one line and prevents a scare.
    var signInGuidanceText: String {
        if appState.isAuthorizing {
            return "Finish signing in to Google in your browser."
        }
        if !appState.hasAccounts {
            return "Sign-in opens in your browser. Google has not verified Mailbell yet, so it shows an "
                + "\"unverified app\" warning: choose Advanced, then continue."
        }
        if appState.canRequestManualRefresh {
            return "Mailbell is notified as mail arrives. Checking manually is only useful after a "
                + "connection problem."
        }
        return "Turn an account back on to watch it for new mail."
    }

    func accountDetailText(for state: AccountRuntimeState) -> String {
        AccountPresentation.detailText(for: state, includeSpam: appState.includeSpam)
    }

    private func joined(_ lines: [String?]) -> String {
        lines.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    /// Browser and Chrome-profile discovery touches the filesystem, so it runs
    /// once when the pane first appears rather than on every redraw.
    func loadWebmailOptionsIfNeeded() async {
        guard !didLoadWebmailOptions else { return }
        didLoadWebmailOptions = true
        webmailBrowsers = BrowserRegistry.browsers()
        chromeProfiles = await ChromeProfileStore.loadProfilesAsync()
    }
}
