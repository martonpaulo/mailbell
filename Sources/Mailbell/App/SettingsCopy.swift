import Foundation

/// Every user-facing string in Settings, in one place.
///
/// Views render prepared copy; they do not compose it. Keeping the wording here
/// means a phrase has exactly one definition, can be read end to end for tone,
/// and can be asserted in tests without standing a view up.
enum SettingsCopy {
    // MARK: - General

    enum MenuBar {
        static let sectionTitle = "Menu Bar"
        static let showCountTitle = "Show the number of messages awaiting review"
        static let showCountDescription =
            "The bell is always visible. Turn this off to keep the menu bar quiet and see the count "
                + "only when you open the menu."
    }

    enum Startup {
        static let sectionTitle = "Startup"
        static let openAtLoginTitle = "Open Mailbell at login"
        static let openAtLoginDescription = "Mailbell watches for mail only while it is running."
        static let loginItemTitle = "Login item"
        static let openLoginItemsSettings = "Open Login Items Settings"
    }

    enum Updates {
        static let sectionTitle = "Updates"
        static let automaticTitle = "Automatically check for updates"
        static let installedVersionTitle = "Installed version"
        static let checkNow = "Check for Updates…"

        static let unavailableDescription =
            "Updates apply to an installed release of Mailbell, not to development builds."
        static let availableDescription =
            "Updates come from GitHub Releases and are checked against Mailbell's signature before "
                + "they replace the app. Update checks never include Gmail data."

        static func description(isUpdaterAvailable: Bool) -> String {
            isUpdaterAvailable ? availableDescription : unavailableDescription
        }
    }

    enum RestoreDefaults {
        static let action = "Restore Defaults…"
        static let confirmAction = "Restore Defaults"
        static let cancel = "Cancel"
        static let confirmTitle = "Restore all settings to their defaults?"
        static let confirmMessage =
            "The menu bar count and watched mailboxes return to their defaults. "
                + "Your Gmail accounts, sign-ins, login item, and notification permission are not affected."
        static let footer =
            "Restoring defaults resets Mailbell's own preferences only. Nothing is removed from Gmail "
                + "and no account is disconnected."
    }

    // MARK: - Notifications

    enum Notifications {
        static let sectionTitle = "Permission"
        static let statusTitle = "Mailbell notifications"
        static let alertsTitle = "Alerts"
        static let soundTitle = "Sound"
        static let badgeTitle = "Badge"
        static let allow = "Allow Notifications…"
        static let openSystemSettings = "Open Notification Settings"
        static let refreshStatus = "Refresh Status"
        static let sendTest = "Send Test Notification"
        static let sendingTestAccessibilityLabel = "Sending test notification"

        static let healthyDescription =
            "Alerts, sound, and badge follow whatever you set for Mailbell in System Settings."
        static let sendingTestFooter = "Sending a test notification…"
        static let defaultFooter =
            "A test notification confirms macOS will actually show Mailbell's alerts. "
                + "Refresh after changing anything in System Settings."

        static func statusDescription(needsAttention: Bool, detail: String) -> String {
            needsAttention ? detail : healthyDescription
        }

        /// The most specific thing we can say right now: an in-flight test, then
        /// the last test result, then the last permission-refresh result.
        static func footer(isSendingTest: Bool, testMessage: String?, statusMessage: String?) -> String {
            if isSendingTest {
                return sendingTestFooter
            }
            return testMessage ?? statusMessage ?? defaultFooter
        }
    }

    // MARK: - Accounts

    enum Accounts {
        static let sectionTitle = "Gmail"
        static let connectedTitle = "Connected"
        static let noAccountValue = "No account yet"
        static let addAccount = "Add Gmail Account…"
        static let checkForNewMail = "Check for New Mail"
        static let openGmail = "Open Gmail"
        static let reconnect = "Reconnect"
        static let signInAgain = "Sign in Again…"
        static let removeAccount = "Remove Account…"
        static let confirmRemoveAction = "Remove Account"
        static let cancel = "Cancel"
        static let watchAccountTitle = "Watch this account for new mail"
        static let statusTitle = "Status"
        static let waitingForSignInAccessibilityLabel = "Waiting for Google sign-in"

        static let removeMessage =
            "Mailbell deletes this account's sign-in from your Keychain and stops watching it. "
                + "Nothing in Gmail changes, and no mail is deleted."

        static func accountCount(_ count: Int) -> String {
            "\(count) \(count == 1 ? "account" : "accounts")"
        }

        static func removeTitle(email: String?) -> String {
            guard let email else { return "Remove this account?" }
            return "Remove \(email)?"
        }

        /// Google's unverified-app screen is the most surprising moment in setup,
        /// so the first-run case names it before the user meets it.
        static func signInGuidance(
            isAuthorizing: Bool,
            hasAccounts: Bool,
            canRefresh: Bool
        ) -> String {
            if isAuthorizing {
                return "Finish signing in to Google in your browser."
            }
            if !hasAccounts {
                return "Sign-in opens in your browser. Google has not verified Mailbell yet, so it shows "
                    + "an \"unverified app\" warning: choose Advanced, then continue."
            }
            if canRefresh {
                return "Mailbell is notified as mail arrives. Checking manually is only useful after a "
                    + "connection problem."
            }
            return "Turn an account back on to watch it for new mail."
        }
    }

    enum WatchedMailboxes {
        static let sectionTitle = "Watched Mailboxes"
        static let inboxTitle = "Inbox"
        static let inboxValue = "Always watched"
        static let spamTitle = "Also watch the Spam folder"
        static let spamDescription =
            "Unread Spam can then reach notifications and the review count. Turning this off also "
                + "clears any Spam already awaiting review. Nothing in Gmail changes either way."
    }

    // MARK: - About

    enum About {
        static let tagline = "Menu bar notifier for Gmail"
        static let developer = "Developed by Marton Paulo"
        static let versionTitle = "Version"
        static let bundleIdentifierTitle = "Bundle ID"
        static let licenseTitle = "License"
        static let licenseValue = "MIT"
        static let supportSectionTitle = "Support"
        static let legalSectionTitle = "Legal"
        static let website = "Mailbell Website"
        static let repository = "Mailbell on GitHub"
        static let issues = "Report an Issue"
        static let latestRelease = "Latest Release"
        static let privacyPolicy = "Privacy Policy"
        static let termsOfService = "Terms of Service"
        static let manageGoogleAccess = "Manage Google Access"

        static let identityFooter =
            "Mailbell runs entirely on this Mac. There is no Mailbell server, and Gmail data never "
                + "leaves your Mac."
        static let supportFooter =
            "The website explains setup, the Google review status, and what Mailbell can access."
        static let legalFooter =
            "Mailbell is in public beta and its Google OAuth client is not verified by Google yet, "
                + "so Google shows an \"unverified app\" screen during sign-in. "
                + "Revoke access at any time in your Google Account."
    }

    // MARK: - Build configuration

    enum BuildProblem {
        static let sectionTitle = "Build Configuration"
        static let headline = "This build is missing its Google OAuth configuration"
        static let explanation =
            "Mailbell releases ship with the Google Desktop OAuth client already configured. "
                + "Seeing this means the build was packaged without it, which no setting can fix."
        static let nextStep =
            "If you downloaded this build from GitHub Releases, please report it. "
                + "If you built Mailbell yourself, set MAILBELL_GOOGLE_CLIENT_ID in .env and reinstall."
        static let reportAction = "Report a Packaging Issue"
        static let detailsDisclosure = "Build Details"
    }
}
