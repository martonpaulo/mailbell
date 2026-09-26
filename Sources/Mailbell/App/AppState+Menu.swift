import AppKit
import MailbellKit

/// The menu bar dropdown's two seams: the presentation derived from the
/// current state, and the commands it sends back.
@MainActor
extension AppState {
    func menuPresentation(now: Date = Date()) -> MenuPresentation {
        var input = MenuPresentation.Input()
        input.accounts = accounts
        input.shownItems = shownItems
        input.conversationSizes = conversationSizes
        input.hiddenConversationCounts = hiddenConversationCounts
        input.reach = reach
        input.canMarkAllAsRead = canMarkAllQueuedAsRead
        input.isMarkingAllAsRead = isMarkingAllAsRead
        input.canCheckForNewMail = canRequestManualRefresh
        input.isAuthorizing = isAuthorizing
        input.notificationsAreOff = notificationAuthorizationState.shouldOpenSystemSettings
        input.buildProblem = buildProblemDetails.map { details in
            MenuPresentation.BuildProblem(headline: SettingsCopy.BuildProblem.headline, details: details)
        }
        input.signInError = signInError
        input.accountStoreError = accountStoreError
        input.lastActionMessage = lastActionMessage
        input.isUpdaterAvailable = isUpdaterAvailable
        input.now = now
        return MenuPresentation(input)
    }

    /// Runs a menu command. Opening Settings needs SwiftUI's environment
    /// action, so the menu passes it in.
    func perform(_ action: MenuCommand.Action, openSettings: () -> Void) {
        switch action {
        case .addAccount:
            addGoogleAccount()
        case .signInAgain(let accountID):
            reauthenticate(accountID: accountID)
        case .reconnect(let accountID):
            reconnect(accountID: accountID)
        case .resumeWatching(let accountID):
            setAccountEnabled(true, accountID: accountID)
        case .openSystemSettings:
            SystemSettings.open()
        case .checkForNewMail:
            refreshMailNow()
        case .openGmail(let accountID):
            openGmail(accountID: accountID)
        case .open(let itemID):
            open(itemID: itemID)
        case .markAsRead(let itemID):
            markAsRead(itemID: itemID)
        case .dismiss(let itemID):
            dismiss(itemID: itemID)
        case .markAllAsRead(let confirmation):
            confirmThenMarkAllAsRead(confirmation)
        case .dismissAll:
            dismissAll()
        case .checkForUpdates:
            checkForUpdates()
        case .settings:
            SettingsWindowPresenter.bringToFront()
            openSettings()
            SettingsWindowPresenter.bringToFront()
        case .quit:
            quit()
        }
    }

    /// A menu cannot host a SwiftUI confirmation dialog, so the confirmation
    /// is a standard alert, shown after the menu has closed.
    private func confirmThenMarkAllAsRead(_ confirmation: MenuConfirmation?) {
        guard let confirmation else {
            markAllAsRead()
            return
        }
        Task { @MainActor in
            let alert = NSAlert()
            alert.messageText = confirmation.title
            alert.informativeText = confirmation.message
            alert.addButton(withTitle: confirmation.confirm)
            alert.addButton(withTitle: confirmation.cancel)
            // An accessory app has no window in front; the alert must be.
            NSApp.activate()
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            markAllAsRead()
        }
    }
}
