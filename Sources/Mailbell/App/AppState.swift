import AppKit
import Foundation
import MailbellKit
import SwiftUI

/// Observable UI state. Owns account supervision and exposes user actions.
@MainActor
@Observable
final class AppState {
    private(set) var status: MonitorStatus = .signedOut
    private(set) var accounts: [AccountRuntimeState] = []
    /// Why the last Google sign-in failed; the menu shows it as a problem row.
    private(set) var signInError: String?
    /// Why saved accounts could not be read; its own problem row, never
    /// overwritten by a sign-in result.
    private(set) var accountStoreError: String?
    private(set) var buildProblemDetails: String?
    private(set) var isAuthorizing = false
    var isSendingTestNotification = false
    var notificationAuthorizationState: NotificationAuthorizationState = .unbundled
    var notificationTestMessage: String?
    var manualRefreshMessage: String?
    private(set) var shownItems: [ReviewItem] = []
    private(set) var shownConversationCounts: [UUID: Int] = [:]
    private(set) var hiddenConversationCounts: [UUID: Int] = [:]
    private(set) var conversationSizes: [String: Int] = [:]
    private(set) var reach = ReviewReach(messages: 0, conversations: 0)
    private(set) var canMarkAllQueuedAsRead = false
    private(set) var menuBarIconSystemImage = MenuBarIcon.idle
    private(set) var needsAttention = false
    private(set) var needsSignIn = false
    private(set) var isMarkingAllAsRead = false
    /// The outcome of the last queue action. An action closes the menu, so
    /// the result has to wait for the next time the menu opens.
    private(set) var lastActionMessage: String?
    private(set) var showsMenuBarCount: Bool
    private(set) var includeSpam: Bool
    private(set) var playNotificationSounds: Bool

    private let settingsStore: AppSettingsStore
    let supervisor: AccountSupervisor
    private let updateManager: UpdateManager
    let notificationManager: NotificationManager
    let launchAtLogin: LaunchAtLoginModel
    @ObservationIgnored var notificationAuthorizationTask: Task<Void, Never>?
    @ObservationIgnored private var activationTask: Task<Void, Never>?

    init(
        settingsStore: AppSettingsStore = AppSettingsStore(),
        updateManager: UpdateManager = UpdateManager(),
        notificationManager: NotificationManager = NotificationManager(),
        launchAtLogin: LaunchAtLoginModel = LaunchAtLoginModel()
    ) {
        self.settingsStore = settingsStore
        self.updateManager = updateManager
        self.notificationManager = notificationManager
        self.launchAtLogin = launchAtLogin
        showsMenuBarCount = settingsStore.showsMenuBarCount
        includeSpam = settingsStore.includeSpam
        playNotificationSounds = settingsStore.playNotificationSounds
        supervisor = AccountSupervisor(notifier: notificationManager, includeSpam: settingsStore.includeSpam)
        supervisor.delegate = self
        accounts = supervisor.accountStates
        status = supervisor.aggregateStatus
        buildProblemDetails = supervisor.buildProblemDetails
        accountStoreError = supervisor.accountStoreError
        syncQueue()

        notificationManager.emailOpenHandler = { [weak self] emailID, accountID, url in
            await self?.supervisor.open(itemID: emailID, accountID: accountID, url: url)
        }
        notificationManager.emailDismissHandler = { [weak self] emailID in
            self?.supervisor.dismiss(itemID: emailID)
        }
        notificationManager.webmailOpenHandler = { [weak self] accountID, url in
            await self?.supervisor.openWebmail(accountID: accountID, url: url)
        }
        refreshNotificationAuthorizationState()
        observeActivation()
    }

    deinit {
        notificationAuthorizationTask?.cancel()
        activationTask?.cancel()
    }

    /// System-owned state can change while Mailbell is in the background (in
    /// System Settings), so it is read again whenever Mailbell becomes active.
    private func observeActivation() {
        activationTask = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: NSApplication.didBecomeActiveNotification) {
                self?.launchAtLogin.refresh()
                self?.refreshNotificationAuthorizationState()
            }
        }
    }

    var hasAccounts: Bool {
        !accounts.isEmpty
    }

    /// Settings' one-line summary of both error sources.
    var lastError: String? {
        signInError ?? accountStoreError
    }

    /// Copies the queue's shape from the supervisor, which is not observable,
    /// so every view that reads it is invalidated together.
    private func syncQueue() {
        shownItems = supervisor.shownItems
        shownConversationCounts = supervisor.reviewQueue.shownConversationCounts
        hiddenConversationCounts = supervisor.hiddenConversationCounts
        conversationSizes = supervisor.reviewQueue.conversationSizes(of: shownItems)
        reach = supervisor.reviewQueue.reach
        canMarkAllQueuedAsRead = supervisor.canMarkAllAsRead
        menuBarIconSystemImage = supervisor.menuBarIconSystemImage
        needsAttention = supervisor.needsAttention
        needsSignIn = supervisor.needsSignIn
    }

    var canRequestManualRefresh: Bool {
        AccountPresentation.canRefresh(accounts) && !isAuthorizing
    }

    func signIn() {
        addGoogleAccount()
    }

    func addGoogleAccount() {
        guard !isAuthorizing else { return }
        Task {
            isAuthorizing = true
            defer { isAuthorizing = false }
            do {
                try await supervisor.addGmailAccount()
                signInError = nil
                buildProblemDetails = supervisor.buildProblemDetails
            } catch {
                Log.auth.error("Sign-in failed: \(Log.detail(error), privacy: .private)")
                signInError = error.localizedDescription
                buildProblemDetails = supervisor.buildProblemDetails
            }
        }
    }

    func reauthenticate(accountID: UUID) {
        guard !isAuthorizing else { return }
        Task {
            isAuthorizing = true
            defer { isAuthorizing = false }
            do {
                try await supervisor.reauthenticate(accountID: accountID)
                signInError = nil
                buildProblemDetails = supervisor.buildProblemDetails
            } catch {
                Log.auth.error("Sign-in failed: \(Log.detail(error), privacy: .private)")
                signInError = error.localizedDescription
                buildProblemDetails = supervisor.buildProblemDetails
            }
        }
    }

    func setAccountEnabled(_ isEnabled: Bool, accountID: UUID) {
        supervisor.setEnabled(isEnabled, accountID: accountID)
    }

    func setShowsMenuBarCount(_ isShown: Bool) {
        guard showsMenuBarCount != isShown else { return }
        showsMenuBarCount = isShown
        settingsStore.showsMenuBarCount = isShown
    }

    func setIncludeSpam(_ isIncluded: Bool) {
        guard includeSpam != isIncluded else { return }
        includeSpam = isIncluded
        settingsStore.includeSpam = isIncluded
        supervisor.setIncludeSpam(isIncluded)
        syncQueue()
    }

    func setPlayNotificationSounds(_ isEnabled: Bool) {
        guard playNotificationSounds != isEnabled else { return }
        playNotificationSounds = isEnabled
        settingsStore.playNotificationSounds = isEnabled
    }

    func shownConversationCount(accountID: UUID) -> Int {
        shownConversationCounts[accountID, default: 0]
    }

    func reconnect(accountID: UUID) {
        supervisor.reconnect(accountID: accountID)
    }

    func removeAccount(accountID: UUID) {
        supervisor.remove(accountID: accountID)
    }

    func updateWebmailPreference(accountID: UUID, preference: WebmailOpenPreference?) {
        supervisor.updateWebmailPreference(accountID: accountID, preference: preference)
    }

    func openGmail(accountID: UUID) {
        Task {
            await supervisor.openGmail(accountID: accountID)
        }
    }

    func open(itemID id: String) {
        clearLastActionResult()
        Task {
            await supervisor.open(itemID: id)
        }
    }

    /// A failed mark reports through the last-action line, naming the message,
    /// because the menu closed before the server answered.
    func markAsRead(itemID id: String) {
        clearLastActionResult()
        let subject = shownItems.first { $0.id == id }?.subject
        Task {
            let didMark = await supervisor.markAsRead(itemID: id)
            if !didMark, let subject {
                lastActionMessage = MenuCopy.markAsReadFailed(subject: MenuPresentation.truncated(subject))
            }
        }
    }

    func dismiss(itemID id: String) {
        clearLastActionResult()
        supervisor.dismiss(itemID: id)
    }

    /// A new action makes the last result stale. Clearing it is what stops
    /// "Marked 5 messages as read" from sitting above a queue it no longer
    /// describes, or beside a different account's later action.
    private func clearLastActionResult() {
        lastActionMessage = nil
    }

    func markAllAsRead() {
        guard !isMarkingAllAsRead else { return }
        Task {
            isMarkingAllAsRead = true
            lastActionMessage = nil
            defer { isMarkingAllAsRead = false }
            lastActionMessage = await supervisor.markAllAsRead().message
        }
    }

    func dismissAll() {
        lastActionMessage = supervisor.dismissAll().message
    }

    var isUpdaterAvailable: Bool {
        updateManager.isAvailable
    }

    var automaticallyChecksForUpdates: Bool {
        updateManager.automaticallyChecksForUpdates
    }

    func setAutomaticallyChecksForUpdates(_ isEnabled: Bool) {
        // UpdateManager is observable too, so a view reading
        // automaticallyChecksForUpdates is invalidated by the updater's own change.
        updateManager.setAutomaticallyChecksForUpdates(isEnabled)
    }

    func checkForUpdates() {
        updateManager.checkForUpdates()
    }

    /// Resets every configurable preference and re-reads it, so the UI and the
    /// supervisor both reflect the stored defaults immediately.
    func restoreDefaults() {
        settingsStore.restoreDefaults()
        showsMenuBarCount = settingsStore.showsMenuBarCount
        playNotificationSounds = settingsStore.playNotificationSounds
        let restoredIncludeSpam = settingsStore.includeSpam
        if includeSpam != restoredIncludeSpam {
            includeSpam = restoredIncludeSpam
            supervisor.setIncludeSpam(restoredIncludeSpam)
        }
        syncQueue()
    }

    func quit() {
        NSApplication.shared.terminate(nil)
    }

    func applyNotificationAuthorizationState(_ state: NotificationAuthorizationState) {
        guard notificationAuthorizationState != state else { return }
        notificationAuthorizationState = state
    }
}

extension AppState: AccountSupervisorDelegate {
    func accountSupervisorDidUpdate(states: [AccountRuntimeState], aggregateStatus: MonitorStatus) {
        accounts = states
        status = aggregateStatus
        buildProblemDetails = supervisor.buildProblemDetails
        accountStoreError = supervisor.accountStoreError
        syncQueue()
    }
}
