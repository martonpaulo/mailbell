import AppKit
import SwiftUI

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

            SettingsRow(
                title: SettingsCopy.Accounts.connectedTitle,
                description: signInGuidanceText
            ) {
                connectedAccountsValue
            }

            SettingsActionRow {
                if appState.isAuthorizing {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel(SettingsCopy.Accounts.waitingForSignInAccessibilityLabel)
                }

                Button(SettingsCopy.Accounts.checkForNewMail) {
                    appState.refreshMailNow()
                }
                .disabled(!appState.canRequestManualRefresh)

                Button(SettingsCopy.Accounts.addAccount) {
                    appState.addGoogleAccount()
                }
                .disabled(appState.oauthSetupMessage != nil || appState.isAuthorizing)
            }
        } header: {
            Text(SettingsCopy.Accounts.sectionTitle)
        } footer: {
            settingsFooter(accountOverviewFooterText)
        }
    }

    /// Applies to every account, so it sits above the per-account sections
    /// rather than hiding behind an "Advanced" pane.
    var watchedMailboxesSection: some View {
        Section {
            SettingsRow(title: SettingsCopy.WatchedMailboxes.inboxTitle) {
                SettingsStatusValue(
                    SettingsCopy.WatchedMailboxes.inboxValue,
                    tone: .success,
                    context: SettingsCopy.WatchedMailboxes.inboxTitle
                )
            }

            SettingsToggleRow(
                title: SettingsCopy.WatchedMailboxes.spamTitle,
                description: SettingsCopy.WatchedMailboxes.spamDescription,
                isOn: Binding(
                    get: { appState.includeSpam },
                    set: { appState.setIncludeSpam($0) }
                )
            )
        } header: {
            Text(SettingsCopy.WatchedMailboxes.sectionTitle)
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
            SettingsToggleRow(
                title: SettingsCopy.Accounts.watchAccountTitle,
                description: accountDetailText(for: state),
                isOn: Binding(
                    get: { state.account.isEnabled },
                    set: { appState.setAccountEnabled($0, accountID: state.account.id) }
                )
            )

            SettingsRow(title: SettingsCopy.Accounts.statusTitle, description: state.lastError) {
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
                Text(SettingsCopy.Accounts.accountCount(appState.accounts.count))
            } else {
                SettingsStatusValue(
                    SettingsCopy.Accounts.noAccountValue,
                    tone: .inactive,
                    context: SettingsCopy.Accounts.connectedTitle
                )
            }
        }
    }

    var accountRemovalTitle: String {
        SettingsCopy.Accounts.removeTitle(email: accountPendingRemoval?.email)
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

    /// One action row per account, ordered the way System Settings orders a
    /// group: the destructive action first, then recovery, then the everyday one.
    func accountActionRow(for state: AccountRuntimeState) -> some View {
        let needsSignIn = AccountRecoveryAction.needed(for: state) == .signInAgain
        return SettingsActionRow {
            if needsSignIn, appState.isAuthorizing {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(SettingsCopy.Accounts.waitingForSignInAccessibilityLabel)
            }

            Button(SettingsCopy.Accounts.removeAccount, role: .destructive) {
                accountPendingRemoval = state.account
            }

            if needsSignIn {
                Button(SettingsCopy.Accounts.signInAgain) {
                    appState.reauthenticate(accountID: state.account.id)
                }
                .disabled(appState.isAuthorizing)
            } else {
                Button(SettingsCopy.Accounts.reconnect) {
                    appState.reconnect(accountID: state.account.id)
                }
                .disabled(!state.account.isEnabled || appState.isAuthorizing)
            }

            Button(SettingsCopy.Accounts.openGmail) {
                appState.openGmail(accountID: state.account.id)
            }
        }
    }

    @ViewBuilder
    func accountStatusValue(for state: AccountRuntimeState) -> some View {
        let title = AccountPresentation.statusText(for: state)
        let context = SettingsCopy.Accounts.statusTitle
        if !state.account.isEnabled {
            SettingsStatusValue(title, tone: .inactive, context: context)
        } else {
            switch state.status {
            case .connected:
                SettingsStatusValue(title, tone: .success, context: context)
            case .connecting, .reconnecting:
                SettingsProgressValue(title, context: context)
            case .signedOut:
                SettingsStatusValue(title, tone: .inactive, context: context)
            case .reauthRequired, .error:
                SettingsStatusValue(title, tone: .error, context: context)
            }
        }
    }

    var accountOverviewFooterText: String {
        [appState.manualRefreshMessage, appState.lastError]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    var signInGuidanceText: String {
        SettingsCopy.Accounts.signInGuidance(
            isAuthorizing: appState.isAuthorizing,
            hasAccounts: appState.hasAccounts,
            canRefresh: appState.canRequestManualRefresh
        )
    }

    func accountDetailText(for state: AccountRuntimeState) -> String {
        AccountPresentation.detailText(for: state, includeSpam: appState.includeSpam)
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
