import SwiftUI

struct AccountActionsMenu: View {
    @ObservedObject var appState: AppState
    let accountState: AccountRuntimeState
    @State private var showsRemoveConfirmation = false

    var body: some View {
        Menu {
            if accountState.status == .reauthRequired {
                Button(appState.isAuthorizing ? "Authorizing..." : "Sign in again") {
                    appState.reauthenticate(accountID: accountState.account.id)
                }
                .disabled(appState.isAuthorizing)
            } else {
                Button("Reconnect Account") {
                    appState.reconnect(accountID: accountState.account.id)
                }
                .disabled(!accountState.account.isEnabled || appState.isAuthorizing)
            }

            Button(accountState.account.isEnabled ? "Disable Account" : "Enable Account") {
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
            Label("Account actions", systemImage: "ellipsis.circle")
                .labelStyle(.iconOnly)
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
}
