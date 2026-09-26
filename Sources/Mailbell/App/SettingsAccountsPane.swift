import AppKit
import MailbellKit
import SwiftUI

/// The Accounts pane, laid out like the account lists in macOS System
/// Settings: one grouped row per account with a status and Details…, then
/// Add Gmail Account… as the section's last row, and the unverified-app note
/// as the section footer. Everything about one account lives in its Details…
/// sheet (`AccountDetailsSheet`).
extension SettingsView {
    var accountsSection: some View {
        Section {
            // A build with no OAuth client cannot sign in at all, so the
            // explanation belongs here, where the person is blocked.
            if let setupMessage = appState.buildProblemDetails {
                BuildProblemPanel(details: setupMessage)
            }

            if appState.hasAccounts {
                ForEach(appState.accounts) { state in
                    accountRow(for: state)
                }
            } else {
                Text(AccountPresentation.overview(appState.accounts))
                    .foregroundStyle(.secondary)
            }

            if let error = appState.lastError {
                SettingsRow(title: SettingsCopy.Accounts.signInFailedTitle, description: error) {
                    EmptyView()
                }
            }

            SettingsActionRow {
                if appState.isAuthorizing {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel(SettingsCopy.Accounts.waitingForSignInAccessibilityLabel)
                    Text(SettingsCopy.Accounts.waitingForSignIn)
                        .foregroundStyle(.secondary)
                }
                Button(SettingsCopy.Accounts.addAccount) {
                    appState.addGoogleAccount()
                }
                .disabled(appState.buildProblemDetails != nil || appState.isAuthorizing)
            }
        } header: {
            Text(SettingsCopy.Accounts.sectionTitle)
        } footer: {
            settingsFooter(SettingsCopy.Accounts.unverifiedNote)
        }
    }

    /// One Spam preference for every account, so it sits in the pane rather
    /// than in one account's sheet, where it would read as per-account.
    var watchedMailboxesSection: some View {
        Section {
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

    func accountRow(for state: AccountRuntimeState) -> some View {
        let email = state.account.email
        return HStack(spacing: Token.Space.md) {
            AccountIconTile()
            Text(email)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: Token.Space.sm)
            AccountStatusLabel(
                text: AccountPresentation.statusText(for: state, includeSpam: appState.includeSpam),
                level: AccountPresentation.statusLevel(for: state)
            )
            Button(SettingsCopy.Accounts.details) {
                accountShowingDetails = AccountDetailsTarget(id: state.account.id)
            }
            .accessibilityLabel(SettingsCopy.Accounts.detailsAccessibilityLabel(email: email))
        }
    }

    var accountDetailsBinding: Binding<AccountDetailsTarget?> {
        Binding(
            get: {
                // A removed account closes its sheet.
                guard let target = accountShowingDetails,
                    appState.accounts.contains(where: { $0.account.id == target.id })
                else { return nil }
                return target
            },
            set: { accountShowingDetails = $0 }
        )
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

/// Which account's Details… sheet is open.
struct AccountDetailsTarget: Identifiable, Equatable {
    let id: UUID
}

/// The envelope tile at the start of an account row, as System Settings shows
/// an icon tile before each account.
private struct AccountIconTile: View {
    var body: some View {
        Image(systemName: "envelope.fill")
            .foregroundStyle(.white)
            .frame(width: Token.Size.accountIconTile, height: Token.Size.accountIconTile)
            .background(
                RoundedRectangle(cornerRadius: Token.Radius.iconTile)
                    .fill(Color.secondary)
            )
            .accessibilityHidden(true)
    }
}

/// An account's status: a coloured dot and the words. The words carry the
/// state, so colour is never the only cue.
struct AccountStatusLabel: View {
    let text: String
    let level: AccountStatusLevel

    var body: some View {
        HStack(spacing: Token.Space.xs) {
            if level == .progress {
                ProgressView()
                    .controlSize(.mini)
            } else {
                Circle()
                    .fill(level.dotColor)
                    .frame(width: Token.Size.statusDot, height: Token.Size.statusDot)
            }
            Text(text)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

extension AccountStatusLevel {
    var dotColor: Color {
        switch self {
        case .active:
            .green
        case .progress, .inactive:
            .secondary
        case .warning:
            .orange
        case .error:
            .red
        }
    }
}
