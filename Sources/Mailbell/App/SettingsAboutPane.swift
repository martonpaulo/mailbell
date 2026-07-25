import AppKit
import SwiftUI
import UserNotifications

/// Identity, version, project links, and legal notices.
extension SettingsView {
    var aboutAppSection: some View {
        Section {
            aboutAppIdentityRow

            LabeledContent("Version") {
                Text(appVersionText)
            }

            LabeledContent("Bundle ID") {
                Text(AppIdentity.bundleIdentifier)
                    .textSelection(.enabled)
            }
        } header: {
            Text("About")
        } footer: {
            settingsFooter(
                "Mailbell runs entirely on this Mac. There is no Mailbell server, and Gmail data never leaves your Mac."
            )
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

                Text("Menu bar notifier for Gmail")
                    .foregroundStyle(.secondary)

                Text("Developed by Marton Paulo")
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
            Link("Mailbell Website", destination: ProjectLinks.website)
            Link("Mailbell on GitHub", destination: ProjectLinks.repository)
            Link("Report an Issue", destination: ProjectLinks.issues)
            Link("Latest Release", destination: ProjectLinks.latestRelease)
        } header: {
            Text("Support")
        } footer: {
            settingsFooter("The website explains setup, the Google review status, and what Mailbell can access.")
        }
    }

    var aboutLegalSection: some View {
        Section {
            Link("Privacy Policy", destination: ProjectLinks.privacyPolicy)
            Link("Terms of Service", destination: ProjectLinks.termsOfService)
            Link("Manage Google Access", destination: ProjectLinks.googleAccountPermissions)
            LabeledContent("License") {
                Text("MIT")
            }
        } header: {
            Text("Legal")
        } footer: {
            settingsFooter(
                "Mailbell is in public beta and its Google OAuth client is not verified by Google yet, "
                    + "so Google shows an \"unverified app\" screen during sign-in. "
                    + "Revoke access at any time in your Google Account."
            )
        }
    }

    var appVersionText: String {
        AppVersion.displayText
    }
}
