import Foundation

/// The one owner of every `UserDefaults` key Mailbell reads or writes (#79).
/// Stores name a key only through this type; `scripts/validate.sh` fails on a
/// key string literal passed to a `UserDefaults` accessor anywhere else.
///
/// Every string is exactly what earlier versions stored, so an upgrade loses no
/// accounts, checkpoints, preferences or handled history. New keys end in
/// `.v1`. The account list and the checkpoint keys predate that rule and keep
/// their unversioned names (docs/architecture.md, "Persistence map").
nonisolated enum StorageKeys {
    // MARK: Preferences, reset by Restore Defaults

    static let showPendingCount = "mailbell.settings.showPendingCount.v1"
    static let includeSpam = "mailbell.settings.includeSpam.v1"
    static let playNotificationSounds = "mailbell.settings.playNotificationSounds.v1"

    /// Every preference Restore Defaults resets. Identity, tokens, account
    /// metadata, IMAP checkpoints, handled-message history and migration state
    /// are user data, not preferences, and are deliberately absent.
    static let settingsConfigurable = [showPendingCount, includeSpam, playNotificationSounds]

    // MARK: User data

    /// The encoded account list. Unversioned; never renamed.
    static let accounts = "mailbell.accounts"

    /// The handled-message history, and the copy kept when it failed to decode.
    static let handledRecords = "mailbell.emailStore.handledRecords.v1"
    static let handledRecordsCorruptBackup = "mailbell.emailStore.handledRecords.corruptBackup.v1"

    /// The two keys of one mailbox's IMAP gap-fill checkpoint.
    struct Checkpoint: Equatable {
        let uidValidity: String
        let lastSeenUID: String
    }

    /// The checkpoint keys for one account's mailbox. Unversioned; never renamed.
    static func checkpoint(accountID: UUID, mailbox: String) -> Checkpoint {
        let namespace = "mailbell.account.\(accountID.uuidString).mailbox.\(mailbox)"
        return Checkpoint(uidValidity: "\(namespace).uidValidity", lastSeenUID: "\(namespace).lastSeenUID")
    }

    // MARK: Migration state

    /// Set once the preferences of the previous bundle identifier were copied (#47).
    static let legacyDomainCopied = "mailbell.migration.legacyDomainCopied.v1"

    // MARK: SwiftUI-owned

    /// SwiftUI restores the last selected Settings tab and the last Settings
    /// window frame from these; screenshot mode pins them.
    static let systemSettingsSelectedTab = "com_apple_SwiftUI_Settings_selectedTabIndex"
    static let systemSettingsWindowFrame = "NSWindow Frame com_apple_SwiftUI_Settings_window"
}
