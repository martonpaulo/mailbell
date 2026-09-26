import Foundation
import MailbellKit
import UserNotifications

/// Every user-facing string in Settings, in one place.
///
/// Views render prepared copy; they do not compose it. Keeping the wording here
/// means a phrase has exactly one definition, can be read end to end for tone,
/// and can be asserted in tests without standing a view up. Each value is read
/// from the String Catalog (`Support/Localizable.xcstrings`); its key is the
/// English text.
enum SettingsCopy {
    // MARK: - General

    /// The app card at the top of General: the icon, the name, a live status
    /// (`GeneralStatus`) and Launch at login.
    enum AppCard {
        static let name = String(localized: "Mailbell")
    }

    enum MenuBar {
        static let sectionTitle = String(localized: "Menu bar", comment: "Settings section header")
        static let showCountTitle = String(localized: "Show count in the menu bar")
        static let showCountDescription = String(
            localized: "Counts conversations to review. The menu always shows the count."
        )
    }

    enum Startup {
        static let launchAtLoginTitle = String(localized: "Launch at login")
        // SMAppService.openSystemSettingsLoginItems() opens this pane itself,
        // so the label names it (#31).
        static let openLoginItemsSettings = String(localized: "Open Login Items Settings…")
        static let requiresApprovalExplanation = String(
            localized: "Mailbell is waiting for your approval in System Settings › General › Login Items & Extensions."
        )
        static let unavailableExplanation = String(
            localized: "Launch at login is available when Mailbell runs from the Applications folder."
        )
        static let changeFailed = String(
            localized:
                "Mailbell couldn't change this setting. Open Mailbell from the Applications folder and try again."
        )

        /// Shown under the toggle; nil when the toggle says everything. A failed
        /// change outranks the status explanation.
        static func note(for status: LoginItemStatus, failed: Bool) -> String? {
            if failed {
                return changeFailed
            }
            switch status {
            case .enabled, .disabled:
                return nil
            case .requiresApproval:
                return requiresApprovalExplanation
            case .unavailable:
                return unavailableExplanation
            }
        }
    }

    enum Notifications {
        static let sectionTitle = String(localized: "Notifications", comment: "Settings section header")
        static let playSoundsTitle = String(localized: "Play notification sounds")
        static let playSoundsDescription = String(localized: "Sound also follows your System Settings.")
        static let testTitle = String(localized: "Test notification")
        static let testDescription = String(localized: "See how new mail looks.")
        static let sendTest = String(localized: "Send Test Notification")
        static let sendingTestAccessibilityLabel = String(localized: "Sending test notification")
        static let testSent = String(localized: "Test notification sent.")

        /// The last test's result replaces the row's explanation until the next
        /// test, so the person sees what happened where they clicked.
        static func testRowDescription(result: String?) -> String {
            result ?? testDescription
        }
    }

    /// Whether macOS lets Mailbell's alerts through. The permission row shows
    /// its value with a status symbol; the Alerts and Sound rows appear only
    /// when macOS has them off.
    enum Permissions {
        static let sectionTitle = String(localized: "Permissions", comment: "Settings section header")
        static let notificationsTitle = String(localized: "Notifications")
        static let notificationsDescription = String(localized: "Needed to alert you about new mail.")
        static let allowed = String(localized: "Allowed")
        static let notAllowed = String(localized: "Not allowed")
        static let notRequested = String(localized: "Not requested")
        static let notAvailable = String(localized: "Not available")
        static let alertsTitle = String(localized: "Alerts")
        static let alertsOffDescription = String(localized: "New mail arrives without a banner.")
        static let soundTitle = String(localized: "Sound")
        static let soundOffDescription = String(localized: "New mail arrives without a sound.")
        static let off = String(localized: "Off")
        static let allow = String(localized: "Allow Notifications…")
        static let openSystemSettings = String(localized: "Open System Settings…")
        /// "Open System Settings…" can only launch the app; macOS decides which
        /// pane shows, so the route is stated in words (#31).
        static let notificationsRoute = String(
            localized: "In System Settings, choose Notifications, then Mailbell, and turn on Allow notifications."
        )

        static func notificationsValue(for state: NotificationAuthorizationState) -> String {
            guard state.isBundled else { return notAvailable }
            switch state.status {
            case .authorized, .provisional:
                return allowed
            case .denied:
                return notAllowed
            case .notDetermined:
                return notRequested
            @unknown default:
                return notAvailable
            }
        }

        /// What the permission is for or, when macOS blocks it, how to fix it.
        static func notificationsRowDescription(for state: NotificationAuthorizationState) -> String {
            guard state.isBundled else { return state.detail }
            return state.isDenied ? notificationsRoute : notificationsDescription
        }
    }

    /// The footer box at the bottom of General: Restore Defaults… leading and
    /// Quit Mailbell… trailing, both confirmed first.
    enum RestoreDefaults {
        static let action = String(localized: "Restore Defaults…")
        static let confirmAction = String(localized: "Restore Defaults")
        static let cancel = String(localized: "Cancel")
        static let confirmTitle = String(localized: "Restore all Mailbell settings?")
        static let confirmMessage = String(
            localized:
                "The menu bar count, notification sounds, and Spam watching return to their original values. Accounts, sign-ins, launch at login, and notification permission are unchanged."
        )
    }

    enum Quit {
        static let action = String(localized: "Quit Mailbell…")
        static let confirmAction = String(localized: "Quit Mailbell")
        static let cancel = String(localized: "Cancel")
        static let confirmTitle = String(localized: "Quit Mailbell?")
        static let confirmMessage = String(
            localized: "Mailbell stops watching for new mail until you open it again."
        )
    }

    // MARK: - Accounts

    /// The Accounts pane follows System Settings: one grouped row per account
    /// with Details…, which opens a sheet holding everything about that account.
    enum Accounts {
        static let sectionTitle = String(localized: "Gmail accounts", comment: "Settings section header")
        static let addAccount = String(localized: "Add Gmail Account…")
        static let details = String(localized: "Details…")
        static let waitingForSignIn = String(localized: "Finish signing in to Google in your browser.")
        static let waitingForSignInAccessibilityLabel = String(localized: "Waiting for Google sign-in")
        static let signInFailedTitle = String(localized: "Sign-in didn't finish")

        /// Google's unverified-app screen is the most surprising moment in
        /// setup, so the note names the exact link to choose and the
        /// 100-new-user cap that can stop sign-in working at all.
        static let unverifiedNote = String(
            localized:
                "Google hasn't verified Mailbell yet. During sign-in, choose Advanced, then “Go to Mailbell (unsafe)”. Until verification, Google allows 100 new users."
        )

        static func detailsAccessibilityLabel(email: String) -> String {
            String(localized: "Details for \(email)…")
        }
    }

    /// Mailbox choices that apply to every account. Spam is one preference
    /// for all accounts, so it sits in the pane, not in one account's sheet.
    enum WatchedMailboxes {
        static let sectionTitle = String(localized: "Watched mailboxes", comment: "Settings section header")
        static let spamTitle = String(localized: "Also watch Spam")
        static let spamDescription = String(
            localized: "Adds unread Spam to alerts and the menu. The Inbox is always watched."
        )
    }

    /// The Details… sheet of one account. Every control names the account in
    /// its accessible name, so it is unambiguous without the sheet's title.
    enum AccountDetails {
        static let done = String(localized: "Done")
        static let watchTitle = String(localized: "Watch for new mail")
        static let watchDescription = String(localized: "Paused accounts stay signed in but send no alerts.")
        static let signInNeededTitle = String(localized: "Sign-in needed")
        static let signInNeededDescription = String(localized: "Google ended this sign-in. Sign in again to resume.")
        static let signInAgain = String(localized: "Sign In Again…")
        static let cannotConnectTitle = String(localized: "Can't connect")
        static let notConnectedTitle = String(localized: "Not connected")
        static let reconnect = String(localized: "Reconnect")
        static let openGmailWith = String(localized: "Open Gmail with")
        static let chromeProfile = String(localized: "Chrome profile")
        nonisolated static let lastChromeProfile = String(localized: "Last profile used in Chrome")
        /// A fallback open still clears the pending item, so the routing
        /// problem has to be visible rather than inferred from mail opening in
        /// the wrong browser.
        static let webmailOpenIssueTitle = String(localized: "Problem opening Gmail")
        static let googleAccessTitle = String(localized: "Google access")
        static let googleAccessDescription = String(
            localized: "Review or remove Mailbell's access in your Google Account."
        )
        static let manageGoogleAccess = String(localized: "Manage Google Access…")
        static let removeAccount = String(localized: "Remove Account…")
        static let confirmRemoveAction = String(localized: "Remove Account")
        static let cancel = String(localized: "Cancel")
        static let openGmail = String(localized: "Open Gmail…")
        static let removeMessage = String(
            localized:
                "Mailbell deletes this account's sign-in from the Keychain and stops watching it. Your mail in Gmail is unchanged."
        )

        static func removeTitle(email: String) -> String {
            String(localized: "Remove \(email)?")
        }

        static func unavailableBrowser(_ name: String) -> String {
            String(localized: "\(name) isn't available. Gmail opens in your default browser.")
        }

        static func unavailableChromeProfile(_ directory: String) -> String {
            String(localized: "The Chrome profile \(directory) isn't available. Gmail opens in the last profile used.")
        }

        /// The problem row at the top of the sheet when the account needs the
        /// person; nil when it needs nothing. Only `AccountRecoveryAction`
        /// decides whether a recovery is offered.
        static func problem(for state: AccountRuntimeState) -> AccountProblem? {
            switch AccountRecoveryAction.needed(for: state) {
            case .signInAgain:
                AccountProblem(
                    title: signInNeededTitle,
                    description: signInNeededDescription,
                    action: .signInAgain
                )
            case .reconnect:
                AccountProblem(
                    title: state.status == .signedOut ? notConnectedTitle : cannotConnectTitle,
                    description: state.lastError,
                    action: .reconnect
                )
            case .enable, nil:
                // A paused account is a choice, and its toggle is the control.
                nil
            }
        }

        static func problemActionTitle(_ action: AccountRecoveryAction) -> String {
            action == .signInAgain ? signInAgain : reconnect
        }

        // MARK: Accessible names

        static func watchAccessibilityLabel(email: String) -> String {
            String(localized: "Watch \(email) for new mail")
        }

        static func openGmailWithAccessibilityLabel(email: String) -> String {
            String(localized: "Open Gmail for \(email) with")
        }

        static func chromeProfileAccessibilityLabel(email: String) -> String {
            String(localized: "Chrome profile for \(email)")
        }

        static func problemActionAccessibilityLabel(_ action: AccountRecoveryAction, email: String) -> String {
            action == .signInAgain
                ? String(localized: "Sign in again to \(email)…")
                : String(localized: "Reconnect \(email)")
        }

        static func manageGoogleAccessAccessibilityLabel(email: String) -> String {
            String(localized: "Manage Google access for \(email)…")
        }

        static func removeAccessibilityLabel(email: String) -> String {
            String(localized: "Remove \(email)…")
        }

        static func openGmailAccessibilityLabel(email: String) -> String {
            String(localized: "Open Gmail for \(email)…")
        }
    }

    /// One account problem: what is wrong, why when known, and the one action
    /// that recovers it.
    struct AccountProblem: Equatable {
        let title: String
        let description: String?
        let action: AccountRecoveryAction
    }

    // MARK: - About

    enum Updates {
        static let sectionTitle = String(localized: "Updates", comment: "Settings section header")
        static let automaticTitle = String(localized: "Automatically check for updates")
        static let checkNow = String(localized: "Check for Updates…")

        static let unavailableDescription = String(
            localized: "Updates apply to an installed release of Mailbell, not to development builds."
        )
        static let availableDescription = String(
            localized:
                "Updates come from GitHub Releases and are checked against Mailbell's signature before they replace the app. Update checks never include Gmail data."
        )

        static func description(isUpdaterAvailable: Bool) -> String {
            isUpdaterAvailable ? availableDescription : unavailableDescription
        }
    }

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

        static let identityFooter = String(
            localized:
                "Mailbell runs entirely on this Mac. There is no Mailbell server, and Gmail data never leaves your Mac."
        )
        static let supportFooter = String(
            localized: "The website explains setup, the Google review status, and what Mailbell can access."
        )
    }

    // MARK: - Build configuration

    enum BuildProblem {
        static let sectionTitle = String(localized: "Build Configuration", comment: "Settings section header")
        static let headline = String(localized: "This build is missing its Google OAuth configuration")
        static let explanation = String(
            localized:
                "Mailbell releases ship with the Google Desktop OAuth client already configured. Seeing this means the build was packaged without it, which no setting can fix."
        )
        static let nextStep = String(
            localized:
                "If you downloaded this build from GitHub Releases, please report it. If you built Mailbell yourself, set MAILBELL_GOOGLE_CLIENT_ID in .env and reinstall."
        )
        static let reportAction = String(localized: "Report a Packaging Issue")
        static let detailsDisclosure = String(localized: "Build Details")
    }
}
