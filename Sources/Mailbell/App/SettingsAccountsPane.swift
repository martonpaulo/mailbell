import AppKit
import SwiftUI
import UserNotifications

/// Connected Gmail accounts: status, recovery actions, and removal.
extension SettingsView {
    var accountOverviewSection: some View {
        Section {
            if let setupMessage = appState.oauthSetupMessage {
                LabeledContent("Build") {
                    SettingsStatusValue("Not configured", tone: .error, context: "Build")
                }
                DisclosureGroup("Build Details") {
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

    var accountSections: some View {
        ForEach(appState.accounts) { state in
            accountSection(for: state)
        }
    }

    func accountSection(for state: AccountRuntimeState) -> some View {
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

    var accountIdentityRows: some View {
        Group {
            LabeledContent("Type") {
                Text("Gmail Account")
            }
        }
    }

    var accountRemovalTitle: String {
        guard let accountPendingRemoval else { return "Remove Account?" }
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

    func accountEnabledTitle(for state: AccountRuntimeState) -> String {
        state.account.isEnabled ? "Disable Account" : "Enable Account"
    }

    @ViewBuilder
    func accountActionRow(for state: AccountRuntimeState) -> some View {
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

    func addAccountButton(title: String) -> some View {
        Button(appState.isAuthorizing ? "Authorizing…" : title) {
            appState.addGoogleAccount()
        }
        .disabled(appState.oauthSetupMessage != nil || appState.isAuthorizing)
        .help(appState.isAuthorizing ? "Complete Google sign-in in your browser." : "Add a Gmail account.")
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
        var lines = [refreshHelpText]
        if let message = appState.manualRefreshMessage {
            lines = [message]
        }
        if let error = appState.lastError {
            lines.append(error)
        }
        return lines.joined(separator: "\n")
    }

    var refreshHelpText: String {
        if appState.isAuthorizing {
            return "Complete Google sign-in in your browser."
        }
        if appState.canRequestManualRefresh {
            return "Checks Gmail for unread messages and updates the review count."
        }
        return "Enable an account to check Gmail."
    }

    func accountFooterText(for state: AccountRuntimeState) -> String {
        var lines = [accountDetailText(for: state)]
        if let error = state.lastError {
            lines.append(error)
        }
        return lines.joined(separator: "\n")
    }

    func accountDetailText(for state: AccountRuntimeState) -> String {
        AccountPresentation.detailText(for: state, includeSpam: appState.includeSpam)
    }
}
