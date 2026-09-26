import MailbellKit
import UserNotifications
import XCTest

@testable import Mailbell

@MainActor
final class SettingsPresentationTests: XCTestCase {
    // MARK: - Panes (#68)

    func testSettingsHasThreePanesWithStableIdentifiers() {
        XCTAssertEqual(SettingsTab.allCases.map(\.title), ["General", "Accounts", "About"])
        XCTAssertEqual(SettingsTab.allCases.map(\.rawValue), ["general", "accounts", "about"])
    }

    // MARK: - System Settings destinations (#31)

    func testSystemSettingsLabelsPromiseOnlyWhatTheButtonDoes() {
        // SystemSettings.open launches the app; macOS decides which pane shows.
        let label = SettingsCopy.Permissions.openSystemSettings
        XCTAssertEqual(label, "Open System Settings\u{2026}")
        XCTAssertFalse(label.contains("Notification Settings"), label)
    }

    func testTheLoginItemsLabelNamesThePaneTheAPIOpens() {
        // SMAppService.openSystemSettingsLoginItems() opens Login Items itself.
        XCTAssertEqual(SettingsCopy.Startup.openLoginItemsSettings, "Open Login Items Settings…")
    }

    func testTheRouteToEachPreferenceIsStatedAsGuidance() {
        XCTAssertTrue(SettingsCopy.Startup.requiresApprovalExplanation.contains("Login Items"))
        XCTAssertTrue(SettingsCopy.Permissions.notificationsRoute.contains("Notifications"))
    }

    // MARK: - General › Permissions (#68)

    func testThePermissionRowStatesTheValueAndTheFixOnlyWhenNeeded() {
        let allowed = permission(.authorized)
        let denied = permission(.denied)
        let undecided = permission(.notDetermined)

        XCTAssertEqual(SettingsCopy.Permissions.notificationsValue(for: allowed), "Allowed")
        XCTAssertEqual(SettingsCopy.Permissions.notificationsValue(for: denied), "Not allowed")
        XCTAssertEqual(SettingsCopy.Permissions.notificationsValue(for: undecided), "Not requested")
        XCTAssertEqual(SettingsCopy.Permissions.notificationsValue(for: .unbundled), "Not available")

        XCTAssertEqual(
            SettingsCopy.Permissions.notificationsRowDescription(for: allowed),
            "Needed to alert you about new mail."
        )
        XCTAssertEqual(
            SettingsCopy.Permissions.notificationsRowDescription(for: denied),
            SettingsCopy.Permissions.notificationsRoute
        )
    }

    func testAlertsAndSoundRowsAppearOnlyWhenMacOSHasThemOff() {
        XCTAssertFalse(permission(.authorized).alertsOff)
        XCTAssertFalse(permission(.authorized).soundOff)
        XCTAssertTrue(permission(.authorized, alert: .disabled).alertsOff)
        XCTAssertTrue(permission(.authorized, sound: .disabled).soundOff)
        // A denied permission is the problem to show; its settings are not.
        XCTAssertFalse(permission(.denied, alert: .disabled, sound: .disabled).alertsOff)
        XCTAssertFalse(permission(.denied, alert: .disabled, sound: .disabled).soundOff)
        XCTAssertFalse(NotificationAuthorizationState.unbundled.alertsOff)
    }

    func testTheTestRowShowsTheLastResultInPlaceOfItsExplanation() {
        XCTAssertEqual(SettingsCopy.Notifications.testRowDescription(result: nil), "See how new mail looks.")
        XCTAssertEqual(
            SettingsCopy.Notifications.testRowDescription(result: "Test notification sent."),
            "Test notification sent."
        )
    }

    // MARK: - Accounts (#68)

    func testRecoveryAppearsOnlyWhenTheAccountNeedsIt() {
        XCTAssertNil(SettingsCopy.AccountDetails.problem(for: account(.connected)))
        XCTAssertNil(SettingsCopy.AccountDetails.problem(for: account(.connecting)))
        XCTAssertNil(SettingsCopy.AccountDetails.problem(for: account(.reconnecting)))
        // A paused account is a choice; its toggle is the control.
        XCTAssertNil(SettingsCopy.AccountDetails.problem(for: account(.error, isEnabled: false)))

        XCTAssertEqual(
            SettingsCopy.AccountDetails.problem(for: account(.signInRequired)),
            SettingsCopy.AccountProblem(
                title: "Sign-in needed",
                description: "Google ended this sign-in. Sign in again to resume.",
                action: .signInAgain
            )
        )
        XCTAssertEqual(
            SettingsCopy.AccountDetails.problem(for: account(.error, lastError: "Gmail refused the connection.")),
            SettingsCopy.AccountProblem(
                title: "Can't connect",
                description: "Gmail refused the connection.",
                action: .reconnect
            )
        )
        XCTAssertEqual(SettingsCopy.AccountDetails.problem(for: account(.signedOut))?.action, .reconnect)
        XCTAssertEqual(SettingsCopy.AccountDetails.problemActionTitle(.signInAgain), "Sign In Again…")
        XCTAssertEqual(SettingsCopy.AccountDetails.problemActionTitle(.reconnect), "Reconnect")
    }

    func testEveryAccountControlNamesItsAccount() {
        let email = "you@gmail.com"
        let names = [
            SettingsCopy.Accounts.detailsAccessibilityLabel(email: email),
            SettingsCopy.AccountDetails.watchAccessibilityLabel(email: email),
            SettingsCopy.AccountDetails.openGmailWithAccessibilityLabel(email: email),
            SettingsCopy.AccountDetails.chromeProfileAccessibilityLabel(email: email),
            SettingsCopy.AccountDetails.problemActionAccessibilityLabel(.signInAgain, email: email),
            SettingsCopy.AccountDetails.problemActionAccessibilityLabel(.reconnect, email: email),
            SettingsCopy.AccountDetails.manageGoogleAccessAccessibilityLabel(email: email),
            SettingsCopy.AccountDetails.removeAccessibilityLabel(email: email),
            SettingsCopy.AccountDetails.openGmailAccessibilityLabel(email: email),
        ]

        for name in names {
            XCTAssertTrue(name.contains(email), name)
        }
        XCTAssertEqual(names[1], "Watch you@gmail.com for new mail")
        XCTAssertEqual(names[0], "Details for you@gmail.com…")
    }

    func testTheRemoveConfirmationNamesTheAccount() {
        XCTAssertEqual(SettingsCopy.AccountDetails.removeTitle(email: "you@gmail.com"), "Remove you@gmail.com?")
    }

    func testRenamedAccountCopy() {
        XCTAssertEqual(SettingsCopy.AccountDetails.webmailOpenIssueTitle, "Problem opening Gmail")
        XCTAssertEqual(SettingsCopy.AccountDetails.lastChromeProfile, "Last profile used in Chrome")
        XCTAssertTrue(SettingsCopy.Accounts.unverifiedNote.contains("“Go to Mailbell (unsafe)”"))
        XCTAssertTrue(SettingsCopy.Accounts.unverifiedNote.contains("100 new users"))
        XCTAssertEqual(
            AccountWebmailSettingsView.chromeProfileOptions(savedDirectory: nil, profiles: []).first?.label,
            "Last profile used in Chrome"
        )
    }

    private func permission(
        _ status: UNAuthorizationStatus,
        alert: UNNotificationSetting = .enabled,
        sound: UNNotificationSetting = .enabled
    ) -> NotificationAuthorizationState {
        NotificationAuthorizationState(isBundled: true, status: status, alertSetting: alert, soundSetting: sound)
    }

    private func account(
        _ status: MonitorStatus,
        isEnabled: Bool = true,
        lastError: String? = nil
    ) -> AccountRuntimeState {
        AccountRuntimeState(
            account: MailAccount(providerID: .gmail, email: "you@gmail.com", isEnabled: isEnabled),
            status: status,
            lastError: lastError
        )
    }
}
