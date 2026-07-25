import SwiftUI

struct AccountWebmailSettingsView: View {
    @ObservedObject var appState: AppState
    let accountState: AccountRuntimeState
    let browsers: [BrowserCandidate]
    let chromeProfiles: [ChromeProfileCandidate]

    @State private var selectedBrowserID = BrowserCandidate.systemDefaultID
    @State private var selectedChromeProfileDirectory = ""
    @State private var isSyncingFromAccount = false

    var body: some View {
        Group {
            // The section header already names the account, so this row says
            // what the control does instead of repeating the address.
            Picker("Open with", selection: $selectedBrowserID) {
                ForEach(browserOptions) { browser in
                    Text(browserLabel(for: browser)).tag(browser.id)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: selectedBrowserID) {
                userChangedPreference()
            }

            if selectedBrowserSupportsChromeProfiles {
                Picker("Chrome profile", selection: $selectedChromeProfileDirectory) {
                    ForEach(chromeProfileOptions) { option in
                        Text(option.label).tag(option.directory)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: selectedChromeProfileDirectory) {
                    userChangedPreference()
                }
            }

            if let warning = missingSelectionWarning {
                webmailProblem(warning)
            }
        }
        .onAppear {
            syncFromAccount()
        }
        .onChange(of: accountState.account.webmailOpenPreference) {
            syncFromAccount()
        }
        .onChange(of: browsers) {
            syncFromAccount()
        }
        .onChange(of: chromeProfiles) {
            syncFromAccount()
        }
    }

    /// A routing problem the user can still act on: the app keeps working by
    /// falling back, so this warns rather than reading as a failure.
    private func webmailProblem(_ message: String) -> some View {
        Label {
            Text(message)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        } icon: {
            Image(systemName: SettingsStatusTone.warning.systemImage)
                .foregroundStyle(SettingsStatusTone.warning.iconColor)
        }
    }

    private var selectedBrowserCandidate: BrowserCandidate {
        BrowserRegistry.candidate(
            matching: accountState.account.webmailOpenPreference,
            browsers: browsers
        )
    }

    private var missingSelectedBrowserID: String? {
        guard !browsers.contains(where: { $0.id == selectedBrowserCandidate.id }) else { return nil }
        guard accountState.account.webmailOpenPreference != nil else { return nil }
        return selectedBrowserCandidate.id
    }

    private var selectedBrowserSupportsChromeProfiles: Bool {
        browserOptions.first(where: { $0.id == selectedBrowserID })?.supportsChromeProfiles == true
    }

    private var chromeProfileOptions: [ChromeProfilePickerOption] {
        Self.chromeProfileOptions(
            savedDirectory: accountState.account.webmailOpenPreference?.chromeProfileDirectory,
            profiles: chromeProfiles
        )
    }

    private var missingChromeProfileDirectory: String? {
        Self.missingChromeProfileDirectory(
            savedDirectory: accountState.account.webmailOpenPreference?.chromeProfileDirectory,
            profiles: chromeProfiles
        )
    }

    private var missingSelectionWarning: String? {
        if let browserID = missingSelectedBrowserID,
           let browser = browserOptions.first(where: { $0.id == browserID }) {
            return "Selected browser is unavailable: \(browser.displayName)."
        }
        if selectedBrowserSupportsChromeProfiles, let missingChromeProfileDirectory {
            return "Selected Chrome profile is unavailable: \(missingChromeProfileDirectory)."
        }
        return nil
    }

    private var browserOptions: [BrowserCandidate] {
        BrowserRegistry.browserOptions(
            matching: accountState.account.webmailOpenPreference,
            browsers: browsers
        )
    }

    private func syncFromAccount() {
        isSyncingFromAccount = true

        if selectedBrowserID != selectedBrowserCandidate.id {
            selectedBrowserID = selectedBrowserCandidate.id
        }

        let profileDirectory = accountState.account.webmailOpenPreference?.chromeProfileDirectory ?? ""
        if selectedChromeProfileDirectory != profileDirectory {
            selectedChromeProfileDirectory = profileDirectory
        }

        Task { @MainActor in
            isSyncingFromAccount = false
        }
    }

    private func userChangedPreference() {
        guard !isSyncingFromAccount else { return }
        persistPreference()
    }

    private func persistPreference() {
        let candidate = browserOptions.first(where: { $0.id == selectedBrowserID }) ?? .systemDefault
        let profile = candidate.supportsChromeProfiles && !selectedChromeProfileDirectory.isEmpty
            ? selectedChromeProfileDirectory
            : nil
        let preference = BrowserRegistry.preference(for: candidate, chromeProfileDirectory: profile)
        guard preference != accountState.account.webmailOpenPreference else { return }
        appState.updateWebmailPreference(accountID: accountState.account.id, preference: preference)
    }

    private func browserLabel(for browser: BrowserCandidate) -> String {
        if browser.id == missingSelectedBrowserID {
            return "\(browser.displayName) (unavailable)"
        }
        return browser.displayName
    }

    nonisolated static func chromeProfileOptions(
        savedDirectory: String?,
        profiles: [ChromeProfileCandidate]
    ) -> [ChromeProfilePickerOption] {
        var options = [
            ChromeProfilePickerOption(directory: "", label: "Default (no explicit profile)")
        ]
        options += profiles.map { profile in
            ChromeProfilePickerOption(directory: profile.directory, label: profile.pickerLabel)
        }
        if let missingDirectory = missingChromeProfileDirectory(
            savedDirectory: savedDirectory,
            profiles: profiles
        ) {
            options.append(
                ChromeProfilePickerOption(directory: missingDirectory, label: "\(missingDirectory) (unavailable)")
            )
        }
        return options
    }

    nonisolated static func missingChromeProfileDirectory(
        savedDirectory: String?,
        profiles: [ChromeProfileCandidate]
    ) -> String? {
        guard let savedDirectory, !savedDirectory.isEmpty else { return nil }
        guard !profiles.contains(where: { $0.directory == savedDirectory }) else { return nil }
        return savedDirectory
    }
}

struct ChromeProfilePickerOption: Identifiable, Equatable {
    let directory: String
    let label: String

    var id: String {
        directory
    }
}
