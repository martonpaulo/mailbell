import AppKit
import SwiftUI
import UserNotifications

/// Identity, version, project links, and legal notices.
extension SettingsView {
    var aboutAppSection: some View {
        Section {
            aboutAppIdentityRow

            SettingsRow(title: SettingsCopy.About.versionTitle) {
                Text(appVersionText)
            }

            SettingsRow(title: SettingsCopy.About.bundleIdentifierTitle) {
                Text(AppIdentity.bundleIdentifier)
                    .textSelection(.enabled)
            }
        } footer: {
            settingsFooter(SettingsCopy.About.identityFooter)
        }
    }

    var aboutAppIdentityRow: some View {
        HStack(spacing: Token.Space.md) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: Token.Size.aboutIcon, height: Token.Size.aboutIcon)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Token.Space.xxs) {
                Text("Mailbell")
                    .font(Token.Font.aboutTitle)
                    .fontWeight(.semibold)

                Text(SettingsCopy.About.tagline)
                    .foregroundStyle(.secondary)

                Text(SettingsCopy.About.developer)
                    .font(Token.Font.secondary)
                    .foregroundStyle(.secondary)
                    .padding(.top, Token.Space.xxs)
            }
        }
        .padding(.vertical, Token.Space.xs)
        .accessibilityElement(children: .combine)
    }

    var aboutLinksSection: some View {
        Section {
            Link(SettingsCopy.About.website, destination: ProjectLinks.website)
            Link(SettingsCopy.About.repository, destination: ProjectLinks.repository)
            Link(SettingsCopy.About.issues, destination: ProjectLinks.issues)
            Link(SettingsCopy.About.latestRelease, destination: ProjectLinks.latestRelease)
        } header: {
            Text(SettingsCopy.About.supportSectionTitle)
        } footer: {
            settingsFooter(SettingsCopy.About.supportFooter)
        }
    }

    var aboutLegalSection: some View {
        Section {
            Link(SettingsCopy.About.privacyPolicy, destination: ProjectLinks.privacyPolicy)
            Link(SettingsCopy.About.termsOfService, destination: ProjectLinks.termsOfService)
            Link(SettingsCopy.About.manageGoogleAccess, destination: ProjectLinks.googleAccountPermissions)
            SettingsRow(title: SettingsCopy.About.licenseTitle) {
                Text(SettingsCopy.About.licenseValue)
            }
        } header: {
            Text(SettingsCopy.About.legalSectionTitle)
        } footer: {
            settingsFooter(SettingsCopy.About.legalFooter)
        }
    }

    var appVersionText: String {
        AppVersion.displayText
    }
}
