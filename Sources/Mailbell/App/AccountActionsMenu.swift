import SwiftUI

struct AccountActionsMenu: View {
    @ObservedObject var appState: AppState
    let accountState: AccountRuntimeState
    @State private var showsRemoveConfirmation = false

    var body: some View {
        Menu {
            if let action = AccountRecoveryAction.needed(for: accountState), action != .enable {
                Button(appState.isAuthorizing && action.requiresAuthorizationSlot ? "Authorizing..." : action.title) {
                    perform(action)
                }
                .disabled(action.requiresAuthorizationSlot && appState.isAuthorizing)
            } else {
                Button("Reconnect") {
                    appState.reconnect(accountID: accountState.account.id)
                }
                .disabled(!accountState.account.isEnabled || appState.isAuthorizing)
            }

            Button(accountState.account.isEnabled ? "Disable" : "Enable") {
                appState.setAccountEnabled(
                    !accountState.account.isEnabled,
                    accountID: accountState.account.id
                )
            }
            .disabled(appState.isAuthorizing)

            Divider()

            Button("Remove Account…", role: .destructive) {
                showsRemoveConfirmation = true
            }
        } label: {
            Label("More...", systemImage: "ellipsis.circle")
        }
        .help("Account actions")
        .confirmationDialog(
            "Remove \(accountState.account.email)?",
            isPresented: $showsRemoveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove Account", role: .destructive) {
                appState.removeAccount(accountID: accountState.account.id)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Mailbell will delete local tokens and stop notifications for this account. "
                    + "Gmail mail will not be changed."
            )
        }
    }

    private func perform(_ action: AccountRecoveryAction) {
        switch action {
        case .enable:
            appState.setAccountEnabled(true, accountID: accountState.account.id)
        case .reconnect:
            appState.reconnect(accountID: accountState.account.id)
        case .signInAgain:
            appState.reauthenticate(accountID: accountState.account.id)
        }
    }
}
