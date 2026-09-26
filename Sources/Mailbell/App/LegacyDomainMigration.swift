import Foundation
import MailbellKit

/// The one-time copy of Mailbell's preferences from the defaults domain of its
/// previous bundle identifier to the current one (#47).
///
/// macOS keys `UserDefaults` to the bundle identifier, so the first launch under
/// the new identifier starts from an empty domain. The old domain is only read
/// and stays in place, so an older build still finds its settings. Keychain
/// tokens are not copied: every account asks to sign in again once, through the
/// existing `signInRequired` path.
///
/// Only names Mailbell owns are copied. A name the current domain already
/// stores keeps its value. `StorageKeys.legacyDomainCopied` records that the
/// copy ran, even when there was nothing to copy; it is migration state, not a
/// preference, so Restore Defaults leaves it alone.
///
/// `ownedShellNames` is the one list of key names outside `StorageKeys`: it
/// names system and Sparkle keys Mailbell never reads itself, only copies.
enum LegacyDomainMigration {
    /// The only place the previous identifier may appear (`scripts/validate.sh`).
    static let legacyDomainName = "com.perso.mailbell"

    /// Accounts, IMAP checkpoints, handled-message records and settings.
    /// Copying the checkpoints lets the first connection after sign-in gap-fill
    /// from the old `lastSeenUID` instead of rebaselining.
    static let ownedPrefix = "mailbell."

    /// System and Sparkle names that hold a user choice. Sparkle's own
    /// bookkeeping (`SULastCheckTime`, `SUUpdateGroupIdentifier`) is not copied.
    static let ownedShellNames: Set<String> = [
        StorageKeys.systemSettingsSelectedTab,
        StorageKeys.systemSettingsWindowFrame,
        "NSStatusItem Preferred Position Item-0",
        "NSStatusItem VisibleCC Item-0",
        "SUEnableAutomaticChecks",
        "SUAutomaticallyUpdate",
        "SUHasLaunchedBefore",
    ]

    static func isOwned(_ name: String) -> Bool {
        name.hasPrefix(ownedPrefix) || ownedShellNames.contains(name)
    }

    /// What to write into the current domain, or nil when the copy already ran.
    /// Always includes the marker when it has not run.
    static func valuesToCopy(legacyDomain: [String: Any]?, currentDomain: [String: Any]) -> [String: Any]? {
        guard currentDomain[StorageKeys.legacyDomainCopied] == nil else { return nil }
        var values: [String: Any] = [:]
        for (name, value) in legacyDomain ?? [:] where isOwned(name) && currentDomain[name] == nil {
            values[name] = value
        }
        values[StorageKeys.legacyDomainCopied] = true
        return values
    }

    /// Runs the copy once for `defaults`, whose persistent domain is `currentDomain`.
    static func migrate(_ defaults: UserDefaults, currentDomain: [String: Any], legacyDomain: [String: Any]?) {
        guard let values = valuesToCopy(legacyDomain: legacyDomain, currentDomain: currentDomain) else {
            return
        }
        for (name, value) in values {
            defaults.set(value, forKey: name)
        }
    }

    /// Called from `MailbellApp.init`, before any store reads `UserDefaults`.
    /// An unbundled build has no domain of its own, and the screenshot bundle
    /// must never inherit the owner's accounts.
    static func runOnLaunch() {
        let identifier = AppIdentity.bundleIdentifier
        guard AppIdentity.isPackagedApp, !ScreenshotMode.isEnabled, identifier != legacyDomainName else {
            return
        }
        let defaults = UserDefaults.standard
        migrate(
            defaults,
            currentDomain: defaults.persistentDomain(forName: identifier) ?? [:],
            legacyDomain: defaults.persistentDomain(forName: legacyDomainName)
        )
    }
}
