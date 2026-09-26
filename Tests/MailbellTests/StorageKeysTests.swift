@testable import Mailbell
import XCTest

/// Pins every stored key to the string earlier versions wrote. A changed string
/// silently loses that value for every user on upgrade, so these literals are
/// the contract, not a restatement of the implementation.
final class StorageKeysTests: XCTestCase {
    func testStoredKeyStringsAreUnchanged() throws {
        XCTAssertEqual(StorageKeys.showPendingCount, "mailbell.settings.showPendingCount.v1")
        XCTAssertEqual(StorageKeys.includeSpam, "mailbell.settings.includeSpam.v1")
        XCTAssertEqual(StorageKeys.playNotificationSounds, "mailbell.settings.playNotificationSounds.v1")
        XCTAssertEqual(StorageKeys.accounts, "mailbell.accounts")
        XCTAssertEqual(StorageKeys.handledRecords, "mailbell.emailStore.handledRecords.v1")
        XCTAssertEqual(
            StorageKeys.handledRecordsCorruptBackup,
            "mailbell.emailStore.handledRecords.corruptBackup.v1"
        )
        XCTAssertEqual(StorageKeys.legacyDomainCopied, "mailbell.migration.legacyDomainCopied.v1")
        XCTAssertEqual(StorageKeys.systemSettingsSelectedTab, "com_apple_SwiftUI_Settings_selectedTabIndex")
        XCTAssertEqual(StorageKeys.systemSettingsWindowFrame, "NSWindow Frame com_apple_SwiftUI_Settings_window")

        let accountID = try XCTUnwrap(UUID(uuidString: "5F0C4E0A-2D6B-4C1E-9F3A-7B8D9E0F1A2B"))
        XCTAssertEqual(
            StorageKeys.checkpoint(accountID: accountID, mailbox: "[Gmail]/Spam"),
            StorageKeys.Checkpoint(
                uidValidity: "mailbell.account.5F0C4E0A-2D6B-4C1E-9F3A-7B8D9E0F1A2B.mailbox.[Gmail]/Spam.uidValidity",
                lastSeenUID: "mailbell.account.5F0C4E0A-2D6B-4C1E-9F3A-7B8D9E0F1A2B.mailbox.[Gmail]/Spam.lastSeenUID"
            )
        )
    }
}
