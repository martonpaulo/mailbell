import SwiftUI

struct AccountActionsMenu: View {
    @ObservedObject var appState: AppState
    let accountState: AccountRuntimeState

    var body: some View {
        Menu {
            if accountState.status == .reauthRequired {
                Button(appState.isAuthorizing ? "Authorizing..." : "Sign in again") {
                    appState.reauthenticate(accountID: accountState.account.id)
                }
                .disabled(appState.isAuthorizing)
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

            Button("Remove", role: .destructive) {
                appState.removeAccount(accountID: accountState.account.id)
            }
        } label: {
            Label("Account actions", systemImage: "ellipsis.circle")
                .labelStyle(.iconOnly)
        }
        .menuStyle(.borderlessButton)
        .help("Account actions")
    }
}
