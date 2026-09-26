import Foundation

/// Every user-facing string in Settings, in one place.
///
/// Views render prepared copy; they do not compose it. Keeping the wording here
/// means a phrase has exactly one definition, can be read end to end for tone,
/// and can be asserted in tests without standing a view up. Each value is read
/// from the String Catalog (`Support/Localizable.xcstrings`); its key is the
/// English text.
enum SettingsCopy {
    // MARK: - General

    enum MenuBar {
        static let sectionTitle = String(localized: "Menu Bar", comment: "Settings section header")
        static let showCountTitle = String(localized: "Show the number of messages awaiting review")
        static let showCountDescription = String(
            localized: "The bell is always visible. Turn this off to keep the menu bar quiet and see the count only when you open the menu."
        )
    }

    enum Startup {
        static let sectionTitle = String(localized: "Startup", comment: "Settings section header")
        static let openAtLoginTitle = String(localized: "Open Mailbell at login")
        static let openAtLoginDescription = String(localized: "Mailbell watches for mail only while it is running.")
        static let loginItemTitle = String(localized: "Login item")
        // SystemSettings.open launches the app; macOS decides which pane is
        // showing, so the label promises only what actually happens and the
        // route is given as guidance instead.
        static let openLoginItemsSettings = String(localized: "Open System Settings…")
        static let loginItemsRoute = String(localized: "In System Settings, go to General → Login Items & Extensions.")
    }

    enum Updates {
        static let sectionTitle = String(localized: "Updates", comment: "Settings section header")
        static let automaticTitle = String(localized: "Automatically check for updates")
        static let installedVersionTitle = String(localized: "Installed version")
        static let checkNow = String(localized: "Check for Updates…")

        static let unavailableDescription = String(
            localized: "Updates apply to an installed release of Mailbell, not to development builds."
        )
        static let availableDescription = String(
            localized: "Updates come from GitHub Releases and are checked against Mailbell's signature before they replace the app. Update checks never include Gmail data."
        )

        static func description(isUpdaterAvailable: Bool) -> String {
            isUpdaterAvailable ? availableDescription : unavailableDescription
        }
    }

    enum RestoreDefaults {
        static let action = String(localized: "Restore Defaults…")
        static let confirmAction = String(localized: "Restore Defaults")
        static let cancel = String(localized: "Cancel")
        static let confirmTitle = String(localized: "Restore all settings to their defaults?")
        static let confirmMessage = String(
            localized: "The menu bar count, notification sound, and watched mailboxes return to their defaults. Your Gmail accounts, sign-ins, login item, and notification permission are not affected."
        )
        static let footer = String(
            localized: "Restoring defaults resets Mailbell's own preferences only. Nothing is removed from Gmail and no account is disconnected."
        )
    }

    // MARK: - Notifications

    enum Notifications {
        static let soundSectionTitle = String(localized: "Sound")
        static let playSoundsTitle = String(localized: "Play notification sounds")
        static let playSoundsDescription = String(
            localized: "When off, notifications stay visual and the menu bar review queue keeps working."
        )
        static let sectionTitle = String(localized: "Permission", comment: "Settings section header")
        static let statusTitle = String(localized: "Mailbell notifications")
        static let alertsTitle = String(localized: "Alerts")
        static let soundTitle = String(localized: "Sound")
        static let badgeTitle = String(localized: "Badge")
        static let allow = String(localized: "Allow Notifications…")
        static let openSystemSettings = String(localized: "Open System Settings…")
        static let notificationsRoute = String(localized: "In System Settings, go to Notifications, then choose Mailbell.")
        static let refreshStatus = String(localized: "Refresh Status")
        static let sendTest = String(localized: "Send Test Notification")
        static let sendingTestAccessibilityLabel = String(localized: "Sending test notification")

        static let healthyDescription = String(
            localized: "macOS controls whether Mailbell's alerts, sound, and badge get through."
        )
        static let sendingTestFooter = String(localized: "Sending a test notification…")
        static let defaultFooter = String(
            localized: "A test notification confirms macOS will actually show Mailbell's alerts. Sound follows both the Mailbell setting above and macOS. Refresh after changing anything in System Settings."
        )

        static func statusDescription(needsAttention: Bool, detail: String) -> String {
            needsAttention ? detail : healthyDescription
        }

        /// The most specific thing we can say right now: an in-flight test, then
        /// the last test result, then the last permission-refresh result.
        static func footer(
            isSendingTest: Bool,
            testMessage: String?,
            statusMessage: String?,
            needsSystemSettings: Bool = false
        ) -> String {
            if isSendingTest {
                return sendingTestFooter
            }
            let text = testMessage ?? statusMessage ?? defaultFooter
            // The button can only launch the app; macOS decides which pane is
            // showing, so the route is stated rather than promised by a label.
            return needsSystemSettings ? "\(text) \(notificationsRoute)" : text
        }
    }

    // MARK: - Accounts

    enum Accounts {
        static let sectionTitle = String(localized: "Gmail", comment: "Settings section header")
        static let connectedTitle = String(localized: "Connected")
        static let noAccountValue = String(localized: "No account yet")
        static let addAccount = String(localized: "Add Gmail Account…")
        static let checkForNewMail = String(localized: "Check for New Mail")
        static let openGmail = String(localized: "Open Gmail")
        /// A fallback open still clears the pending item, so the routing
        /// problem has to be visible rather than inferred from mail opening in
        /// the wrong browser.
        static let webmailOpenIssueTitle = String(localized: "Last Open Gmail")
        static let reconnect = String(localized: "Reconnect")
        static let signInAgain = String(localized: "Sign in Again…")
        static let removeAccount = String(localized: "Remove Account…")
        static let confirmRemoveAction = String(localized: "Remove Account")
        static let cancel = String(localized: "Cancel")
        static let watchAccountTitle = String(localized: "Watch this account for new mail")
        static let statusTitle = String(localized: "Status")
        static let waitingForSignInAccessibilityLabel = String(localized: "Waiting for Google sign-in")

        static let removeMessage = String(
            localized: "Mailbell deletes this account's sign-in from your Keychain and stops watching it. Nothing in Gmail changes, and no mail is deleted."
        )

        static func accountCount(_ count: Int) -> String {
            count == 1 ? String(localized: "1 account") : String(localized: "\(count) accounts")
        }

        static func removeTitle(email: String?) -> String {
            guard let email else { return String(localized: "Remove this account?") }
            return String(localized: "Remove \(email)?")
        }

        /// Google's unverified-app screen is the most surprising moment in setup,
        /// so the first-run case names it before the user meets it.
        static func signInGuidance(
            isAuthorizing: Bool,
            hasAccounts: Bool,
            canRefresh: Bool
        ) -> String {
            if isAuthorizing {
                return String(localized: "Finish signing in to Google in your browser.")
            }
            if !hasAccounts {
                // Both halves are required disclosure: the warning a user will
                // see, and the cap that can stop sign-in working at all.
                return String(
                    localized: "Sign-in opens in your browser. Google has not verified Mailbell yet, so it shows an \"unverified app\" warning: choose Advanced, then continue. Google also caps unverified apps at 100 new users, so sign-in can stop working for new people until verification completes."
                )
            }
            if canRefresh {
                return String(
                    localized: "Mailbell is notified as mail arrives. Checking manually is only useful after a connection problem."
                )
            }
            return String(localized: "Turn an account back on to watch it for new mail.")
        }
    }

    enum WatchedMailboxes {
        static let sectionTitle = String(localized: "Watched Mailboxes", comment: "Settings section header")
        static let inboxTitle = String(localized: "Inbox")
        static let inboxValue = String(localized: "Always watched")
        static let spamTitle = String(localized: "Also watch the Spam folder")
        static let spamDescription = String(
            localized: "Unread Spam can then reach notifications and the review count. Turning this off also clears any Spam already awaiting review. Nothing in Gmail changes either way."
        )
    }

    // MARK: - About

    enum About {
        static let tagline = String(localized: "Menu bar notifier for Gmail")
        static let developer = String(localized: "Developed by Marton Paulo")
        static let versionTitle = String(localized: "Version")
        static let bundleIdentifierTitle = String(localized: "Bundle ID")
        static let licenseTitle = String(localized: "License")
        static let licenseValue = String(localized: "MIT")
        static let supportSectionTitle = String(localized: "Support", comment: "Settings section header")
        static let legalSectionTitle = String(localized: "Legal", comment: "Settings section header")
        static let website = String(localized: "Mailbell Website")
        static let repository = String(localized: "Mailbell on GitHub")
        static let issues = String(localized: "Report an Issue")
        static let latestRelease = String(localized: "Latest Release")
        static let privacyPolicy = String(localized: "Privacy Policy")
        static let termsOfService = String(localized: "Terms of Service")
        static let manageGoogleAccess = String(localized: "Manage Google Access")

        static let identityFooter = String(
            localized: "Mailbell runs entirely on this Mac. There is no Mailbell server, and Gmail data never leaves your Mac."
        )
        static let supportFooter = String(
            localized: "The website explains setup, the Google review status, and what Mailbell can access."
        )
        static let legalFooter = String(
            localized: "Mailbell is in public beta and its Google OAuth client is not verified by Google yet, so Google shows an \"unverified app\" screen during sign-in and caps unverified apps at 100 new users. Revoke access at any time in your Google Account."
        )
    }

    // MARK: - Build configuration

    enum BuildProblem {
        static let sectionTitle = String(localized: "Build Configuration", comment: "Settings section header")
        static let headline = String(localized: "This build is missing its Google OAuth configuration")
        static let explanation = String(
            localized: "Mailbell releases ship with the Google Desktop OAuth client already configured. Seeing this means the build was packaged without it, which no setting can fix."
        )
        static let nextStep = String(
            localized: "If you downloaded this build from GitHub Releases, please report it. If you built Mailbell yourself, set MAILBELL_GOOGLE_CLIENT_ID in .env and reinstall."
        )
        static let reportAction = String(localized: "Report a Packaging Issue")
        static let detailsDisclosure = String(localized: "Build Details")
    }
}
