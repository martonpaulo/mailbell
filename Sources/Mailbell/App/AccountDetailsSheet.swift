import AppKit
import MailbellKit
import SwiftUI

/// Everything about one account, in a sheet opened by its Details… button, as
/// the Wi-Fi details sheet in System Settings: a problem row only when the
/// account needs the person, its settings, Google access, and a bottom bar with
/// Remove Account… leading and Open Gmail… and Done trailing.
///
/// Every control carries the address in its accessible name, so a VoiceOver
/// user always knows which account a control changes.
struct AccountDetailsSheet: View {
    let appState: AppState
    let accountID: UUID
    let browsers: [BrowserCandidate]
    let chromeProfiles: [ChromeProfileCandidate]

    @Environment(\.dismiss) private var dismiss
    @State private var showsRemoveConfirmation = false

    var body: some View {
        if let state = appState.accounts.first(where: { $0.account.id == accountID }) {
            content(for: state)
        }
    }

    private func content(for state: AccountRuntimeState) -> some View {
        let email = state.account.email
        return VStack(alignment: .leading, spacing: 0) {
            Text(email)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, Token.Space.xl)
                .padding(.top, Token.Space.lg)

            Form {
                Section {
                    if let problem = SettingsCopy.AccountDetails.problem(for: state) {
                        problemRow(problem, email: email)
                    }

                    SettingsToggleRow(
                        title: SettingsCopy.AccountDetails.watchTitle,
                        description: SettingsCopy.AccountDetails.watchDescription,
                        isOn: Binding(
                            get: { state.account.isEnabled },
                            set: { appState.setAccountEnabled($0, accountID: state.account.id) }
                        )
                    )
                    .accessibilityLabel(SettingsCopy.AccountDetails.watchAccessibilityLabel(email: email))

                    AccountWebmailSettingsView(
                        appState: appState,
                        accountState: state,
                        browsers: browsers,
                        chromeProfiles: chromeProfiles
                    )

                    // A fallback open still clears the pending item, so the
                    // routing problem has to be visible where it can be fixed.
                    if let error = state.webmailOpenError {
                        SettingsRow(title: SettingsCopy.AccountDetails.webmailOpenIssueTitle, description: error) {
                            EmptyView()
                        }
                    }
                }

                Section {
                    SettingsRow(
                        title: SettingsCopy.AccountDetails.googleAccessTitle,
                        description: SettingsCopy.AccountDetails.googleAccessDescription
                    ) {
                        SettingsActionRow {
                            Button(SettingsCopy.AccountDetails.manageGoogleAccess) {
                                NSWorkspace.shared.open(ProjectLinks.googleAccountPermissions)
                            }
                            .accessibilityLabel(
                                SettingsCopy.AccountDetails.manageGoogleAccessAccessibilityLabel(email: email)
                            )
                        }
                    }
                }
            }
            .formStyle(.grouped)

            bottomBar(for: state)
                .padding(.horizontal, Token.Space.xl)
                .padding(.bottom, Token.Space.lg)
        }
        .frame(width: Token.Size.accountSheetWidth)
    }

    private func problemRow(_ problem: SettingsCopy.AccountProblem, email: String) -> some View {
        SettingsRow(title: problem.title, description: problem.description) {
            SettingsActionRow {
                if problem.action.requiresAuthorizationSlot, appState.isAuthorizing {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel(SettingsCopy.Accounts.waitingForSignInAccessibilityLabel)
                }
                Button(SettingsCopy.AccountDetails.problemActionTitle(problem.action)) {
                    perform(problem.action)
                }
                .disabled(appState.isAuthorizing)
                .accessibilityLabel(
                    SettingsCopy.AccountDetails.problemActionAccessibilityLabel(problem.action, email: email)
                )
            }
        }
    }

    private func bottomBar(for state: AccountRuntimeState) -> some View {
        let email = state.account.email
        return SettingsActionRow {
            Button(SettingsCopy.AccountDetails.removeAccount) {
                showsRemoveConfirmation = true
            }
            .accessibilityLabel(SettingsCopy.AccountDetails.removeAccessibilityLabel(email: email))
            .confirmationDialog(
                SettingsCopy.AccountDetails.removeTitle(email: email),
                isPresented: $showsRemoveConfirmation,
                titleVisibility: .visible
            ) {
                Button(SettingsCopy.AccountDetails.confirmRemoveAction, role: .destructive) {
                    appState.removeAccount(accountID: state.account.id)
                    dismiss()
                }
                Button(SettingsCopy.AccountDetails.cancel, role: .cancel) {}
            } message: {
                Text(SettingsCopy.AccountDetails.removeMessage)
            }
        } trailing: {
            Button(SettingsCopy.AccountDetails.openGmail) {
                appState.openGmail(accountID: state.account.id)
            }
            .accessibilityLabel(SettingsCopy.AccountDetails.openGmailAccessibilityLabel(email: email))

            Button(SettingsCopy.AccountDetails.done) {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
    }

    private func perform(_ action: AccountRecoveryAction) {
        switch action {
        case .enable:
            appState.setAccountEnabled(true, accountID: accountID)
        case .reconnect:
            appState.reconnect(accountID: accountID)
        case .signInAgain:
            appState.reauthenticate(accountID: accountID)
        }
    }
}
