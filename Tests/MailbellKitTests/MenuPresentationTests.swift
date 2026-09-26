import XCTest

@testable import MailbellKit

/// The menu bar dropdown's content, derived without AppKit: what each state
/// shows, in which order, in which unit and with which words (#69).
@MainActor
final class MenuPresentationTests: XCTestCase {
    private let ana = ReviewQueueFixture.makeAccount(id: "11111111-1111-1111-1111-111111111111", email: "ana@gmail.com")
    private let team = ReviewQueueFixture.makeAccount(
        id: "22222222-2222-2222-2222-222222222222",
        email: "team@studio.example"
    )
    /// Friday 25 September 2026, 12:00 UTC.
    private let now = Date(timeIntervalSince1970: 1_790_337_600)

    // MARK: - States

    func testNoAccountOffersOnlyAddAccountSettingsAndQuit() {
        let menu = MenuPresentation(input())

        XCTAssertEqual(menu.problems, [])
        XCTAssertEqual(
            menu.body,
            .noAccount(
                message: "No Gmail account",
                addAccount: MenuCommand(title: "Add Gmail Account…", action: .addAccount)
            )
        )
        XCTAssertEqual(menu.accounts, [])
        XCTAssertEqual(menu.footer.map(\.title), ["Settings…", "Quit Mailbell"])
    }

    func testAddAccountWaitsWhileSigningInAndStopsOnABuildProblem() {
        var signingIn = input()
        signingIn.isAuthorizing = true
        XCTAssertEqual(
            addAccountCommand(MenuPresentation(signingIn)),
            MenuCommand(title: "Signing In…", action: .addAccount, isEnabled: false)
        )

        var broken = input()
        broken.buildProblem = .init(headline: "This build is missing its Google OAuth configuration", details: "x")
        let menu = MenuPresentation(broken)
        XCTAssertEqual(addAccountCommand(menu)?.isEnabled, false)
        XCTAssertEqual(menu.problems.map(\.title), ["This build is missing its Google OAuth configuration"])
    }

    func testNothingToReviewKeepsCheckForNewMail() {
        var state = input(accounts: [connected(ana)])
        state.canCheckForNewMail = true
        let queue = queue(MenuPresentation(state))

        XCTAssertNil(queue?.header)
        XCTAssertEqual(queue?.emptyText, "Nothing to review")
        XCTAssertNil(queue?.bulk)
        XCTAssertEqual(queue?.checkForNewMail, MenuCommand(title: "Check for New Mail", action: .checkForNewMail))
        XCTAssertEqual(queue?.groups, [])
    }

    func testSignInExpiredShowsAProblemRowWithItsFix() {
        let state = AccountRuntimeState(account: ana, status: .signInRequired)
        let menu = MenuPresentation(input(accounts: [state]))

        XCTAssertEqual(menu.problems.count, 1)
        XCTAssertEqual(menu.problems.first?.title, "ana@gmail.com needs sign-in")
        XCTAssertEqual(
            menu.problems.first?.subtitle,
            "Mailbell can't watch this account until you sign in again."
        )
        XCTAssertEqual(
            menu.problems.first?.command,
            MenuCommand(title: "Sign In Again…", action: .signInAgain(accountID: ana.id))
        )
    }

    func testAConnectionErrorShowsItsReasonAndReconnect() {
        let state = AccountRuntimeState(account: ana, status: .error, lastError: "The connection timed out.")
        let problem = MenuPresentation(input(accounts: [state])).problems.first

        XCTAssertEqual(problem?.title, "Can't connect to ana@gmail.com")
        XCTAssertEqual(problem?.subtitle, "The connection timed out.")
        XCTAssertEqual(problem?.command, MenuCommand(title: "Reconnect", action: .reconnect(accountID: ana.id)))
    }

    func testAPausedAccountIsNotAProblem() {
        var paused = ana
        paused.isEnabled = false
        let menu = MenuPresentation(input(accounts: [AccountRuntimeState(account: paused, status: .signInRequired)]))

        XCTAssertEqual(menu.problems, [])
        XCTAssertEqual(menu.accounts.first?.details.first, "Paused")
        XCTAssertEqual(
            menu.accounts.first?.commands.last,
            MenuCommand(title: "Resume Watching", action: .resumeWatching(accountID: ana.id))
        )
    }

    func testNotificationsOffPointsToSystemSettings() {
        var state = input(accounts: [connected(ana)])
        state.notificationsAreOff = true
        let problem = MenuPresentation(state).problems.first

        XCTAssertEqual(problem?.title, "Notifications are off")
        XCTAssertEqual(problem?.subtitle, "In System Settings, go to Notifications, then choose Mailbell.")
        XCTAssertEqual(problem?.command, MenuCommand(title: "Open System Settings", action: .openSystemSettings))
    }

    func testSignInAndAccountStoreErrorsHaveTheirOwnRows() {
        var state = input()
        state.accountStoreError = "Couldn't read saved accounts."
        state.signInError = "Google sign-in is already in progress."
        let problems = MenuPresentation(state).problems

        XCTAssertEqual(problems.map(\.id), ["accountStore", "signIn"])
        XCTAssertEqual(
            problems.map(\.title), ["Couldn't read saved accounts.", "Google sign-in is already in progress."])
    }

    // MARK: - Rows and grouping

    func testARowShowsTheSenderAboveTheSubjectAndTime() throws {
        let store = ReviewQueueFixture.makeStore()
        try admit(store, uid: 1, from: "Lucía Ortega <lucia@example.com>", subject: "Flight change", minutesAgo: 22)
        let menu = MenuPresentation(input(accounts: [connected(ana)], store: store))
        let group = try XCTUnwrap(queue(menu)?.groups.first)
        let row = try XCTUnwrap(group.rows.first)

        XCTAssertNil(group.header, "one account needs no header")
        XCTAssertEqual(row.title, "Lucía Ortega")
        XCTAssertEqual(row.subtitle, "Flight change · 11:38\u{202F}AM")
        XCTAssertEqual(row.sender, "Lucía Ortega <lucia@example.com>")
        XCTAssertTrue(row.recipient.hasPrefix("To ana@gmail.com · "))
        XCTAssertEqual(row.subjectLines, [])
        XCTAssertEqual(
            row.commands.map(\.title),
            ["Open in Gmail", "Mark as Read in Gmail", "Dismiss (Keep Unread in Gmail)"]
        )
    }

    func testMoreThanOneAccountGroupsRowsUnderEachAddress() throws {
        let store = ReviewQueueFixture.makeStore()
        try admit(store, uid: 1, account: ana)
        try admit(store, uid: 2, account: team)
        try admit(store, uid: 3, account: team)
        let menu = MenuPresentation(input(accounts: [connected(ana), connected(team)], store: store))
        let groups = try XCTUnwrap(queue(menu)?.groups)

        XCTAssertEqual(groups.map(\.header), ["ana@gmail.com", "team@studio.example"])
        XCTAssertEqual(groups.map(\.rows.count), [1, 2])
        XCTAssertTrue(groups[1].rows.allSatisfy { $0.recipient.hasPrefix("To team@studio.example") })
        XCTAssertEqual(queue(menu)?.header, "3 conversations to review")
        XCTAssertEqual(
            menu.accounts.map(\.details),
            [
                ["Watching Inbox", "1 conversation to review"],
                ["Watching Inbox", "2 conversations to review"],
            ])
    }

    func testAConversationShowsItsMessageCount() throws {
        let store = ReviewQueueFixture.makeStore()
        for uid in 1...3 {
            try admit(store, uid: uid, from: "Theo Park <theo@example.com>", thread: "offsite")
        }
        let row = try XCTUnwrap(
            queue(MenuPresentation(input(accounts: [connected(ana)], store: store)))?.groups[0].rows[0])

        XCTAssertEqual(row.title, "Theo Park (3)")
    }

    func testARowThatCannotBeMarkedHidesTheCommand() throws {
        let store = ReviewQueueFixture.makeStore()
        try admit(store, uid: 1, uidValidity: 0)
        let row = try XCTUnwrap(
            queue(MenuPresentation(input(accounts: [connected(ana)], store: store)))?.groups[0].rows[0])

        XCTAssertEqual(row.commands.map(\.title), ["Open in Gmail", "Dismiss (Keep Unread in Gmail)"])
    }

    func testLongTitlesAreCutAndTheSubmenuKeepsTheFullSubject() throws {
        let subject = "Quarterly planning notes for the design, engineering and support teams, second draft"
        let store = ReviewQueueFixture.makeStore()
        try admit(store, uid: 1, subject: subject)
        let row = try XCTUnwrap(
            queue(MenuPresentation(input(accounts: [connected(ana)], store: store)))?.groups[0].rows[0])

        XCTAssertTrue(row.subtitle.hasPrefix(MenuPresentation.truncated(subject) + " · "))
        XCTAssertEqual(row.subjectLines.joined(separator: " "), subject)
        XCTAssertTrue(row.subjectLines.allSatisfy { $0.count <= MenuPresentation.lineLimit })
    }

    func testPreviewIsAtMostThreeSingleLines() throws {
        let preview = Array(repeating: "The airline moved our Thursday flight and kept the same seats.", count: 5)
            .joined(separator: "\n")
        let store = ReviewQueueFixture.makeStore()
        try admit(store, uid: 1, preview: preview)
        let row = try XCTUnwrap(
            queue(MenuPresentation(input(accounts: [connected(ana)], store: store)))?.groups[0].rows[0])

        XCTAssertEqual(row.previewLines.count, 3)
        XCTAssertTrue(row.previewLines.allSatisfy { $0.count <= MenuPresentation.lineLimit })
        XCTAssertEqual(row.previewLines.last?.last, "…")
    }

    func testTheCappedQueueEndsWithTheOverflowLine() throws {
        let store = ReviewQueueFixture.makeStore()
        let conversations = ReviewQueueBudget.shownConversationsPerAccount + 6
        for uid in 1...conversations {
            try admit(store, uid: uid)
        }
        let group = try XCTUnwrap(
            queue(MenuPresentation(input(accounts: [connected(ana)], store: store)))?.groups.first)

        XCTAssertEqual(group.rows.count, ReviewQueueBudget.shownConversationsPerAccount)
        XCTAssertEqual(group.overflow, "6 more conversations not shown. Open Gmail to see them.")
    }

    // MARK: - Bulk actions and counting unit

    func testTheBulkSubmenuStatesItsReachInBothUnits() throws {
        let store = ReviewQueueFixture.makeStore()
        try admit(store, uid: 1, thread: "a")
        try admit(store, uid: 2, thread: "a")
        try admit(store, uid: 3, thread: "b")
        var state = input(accounts: [connected(ana)], store: store)
        state.canMarkAllAsRead = true
        let bulk = try XCTUnwrap(queue(MenuPresentation(state))?.bulk)

        XCTAssertEqual(bulk.title, "All Conversations")
        XCTAssertEqual(bulk.scope, "Includes 3 messages in 2 conversations.")
        XCTAssertEqual(
            bulk.commands.map(\.title), ["Mark All as Read in Gmail…", "Dismiss All (Keep Unread in Gmail)"])
    }

    func testMarkAllConfirmsOnlyWhenItReachesHiddenMessages() {
        XCTAssertNil(
            MenuPresentation.bulkConfirmation(reach: ReviewReach(messages: 12, conversations: 12), visibleRows: 12))

        let one = MenuPresentation.bulkConfirmation(
            reach: ReviewReach(messages: 13, conversations: 12), visibleRows: 12)
        XCTAssertEqual(one?.title, "Mark 13 messages as read in Gmail?")
        XCTAssertEqual(
            one?.message,
            "1 of them isn't shown in the menu. Gmail shows them as read on all your devices."
        )

        let many = MenuPresentation.bulkConfirmation(
            reach: ReviewReach(messages: 37, conversations: 12), visibleRows: 12)
        XCTAssertEqual(many?.title, "Mark 37 messages as read in Gmail?")
        XCTAssertEqual(
            many?.message,
            "25 of them aren't shown in the menu. Gmail shows them as read on all your devices."
        )
        XCTAssertEqual(many?.confirm, "Mark as Read")
        XCTAssertEqual(many?.cancel, "Cancel")
    }

    func testWithoutHiddenMessagesMarkAllActsAtOnce() throws {
        let store = ReviewQueueFixture.makeStore()
        try admit(store, uid: 1)
        var state = input(accounts: [connected(ana)], store: store)
        state.canMarkAllAsRead = true
        let command = try XCTUnwrap(queue(MenuPresentation(state))?.bulk?.commands.first)

        XCTAssertEqual(
            command, MenuCommand(title: "Mark All as Read in Gmail", action: .markAllAsRead(confirmation: nil)))
    }

    func testTheLastActionLineSitsInTheQueue() {
        var state = input(accounts: [connected(ana)])
        state.lastActionMessage = MenuCopy.markAsReadFailed(subject: "Flight change")

        XCTAssertEqual(
            queue(MenuPresentation(state))?.lastAction,
            "Couldn't mark “Flight change” as read in Gmail. Try again."
        )
    }

    // MARK: - Footer

    func testTheFooterHidesUpdatesWithoutAnUpdaterAndKeepsNativeShortcuts() {
        let withoutUpdater = MenuPresentation(input(accounts: [connected(ana)]))
        XCTAssertEqual(withoutUpdater.footer.map(\.title), ["Settings…", "Quit Mailbell"])
        XCTAssertEqual(withoutUpdater.footer.map(\.keyEquivalent), [",", "q"])

        var state = input(accounts: [connected(ana)])
        state.isUpdaterAvailable = true
        XCTAssertEqual(
            MenuPresentation(state).footer.map(\.title),
            ["Check for Updates…", "Settings…", "Quit Mailbell"]
        )
    }

    // MARK: - Helpers for single-line items

    func testTruncationCutsAtTheLimit() {
        let exact = String(repeating: "a", count: MenuPresentation.lineLimit)
        XCTAssertEqual(MenuPresentation.truncated(exact), exact)

        let long = String(repeating: "a", count: MenuPresentation.lineLimit + 1)
        let cut = MenuPresentation.truncated(long)
        XCTAssertEqual(cut.count, MenuPresentation.lineLimit)
        XCTAssertEqual(cut.last, "…")
    }

    func testRowTimeIsAsShortAsTheDateAllows() {
        func time(daysAgo: Int) -> String {
            MenuPresentation.rowTime(
                for: now.addingTimeInterval(TimeInterval(-daysAgo * 86_400)),
                now: now,
                calendar: calendar,
                locale: locale
            )
        }
        XCTAssertEqual(time(daysAgo: 0), "12:00\u{202F}PM", "the short time style uses a narrow no-break space")
        XCTAssertEqual(time(daysAgo: 1), "Yesterday")
        XCTAssertEqual(time(daysAgo: 3), "Tuesday")
        XCTAssertEqual(time(daysAgo: 30), "Aug 26")
        XCTAssertEqual(time(daysAgo: 400), "Aug 21, 2025")
    }

    // MARK: - Fixtures

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }

    private var locale: Locale {
        Locale(identifier: "en_US")
    }

    private func input(accounts: [AccountRuntimeState] = [], store: ReviewQueue? = nil) -> MenuPresentation.Input {
        var input = MenuPresentation.Input()
        input.accounts = accounts
        input.now = now
        input.calendar = calendar
        input.locale = locale
        if let store {
            input.shownItems = store.shownItems
            input.conversationSizes = store.conversationSizes(of: store.shownItems)
            input.reach = store.reach
            input.hiddenConversationCounts = accounts.reduce(into: [:]) { counts, state in
                counts[state.id] = store.hiddenConversationCount(accountID: state.id)
            }
        }
        return input
    }

    private func connected(_ account: MailAccount) -> AccountRuntimeState {
        AccountRuntimeState(account: account, status: .connected)
    }

    private func queue(_ menu: MenuPresentation) -> MenuQueue? {
        guard case .queue(let queue) = menu.body else { return nil }
        return queue
    }

    private func addAccountCommand(_ menu: MenuPresentation) -> MenuCommand? {
        guard case .noAccount(_, let command) = menu.body else { return nil }
        return command
    }

    private func admit(
        _ store: ReviewQueue,
        uid: Int,
        account: MailAccount? = nil,
        from: String = "Sender <sender@example.com>",
        subject: String? = nil,
        thread: String? = nil,
        preview: String? = nil,
        minutesAgo: Int? = nil,
        uidValidity: Int = 1
    ) throws {
        let header = MessageHeader(
            uid: uid,
            mailboxName: "INBOX",
            from: from,
            subject: subject ?? "Subject \(uid)",
            date: "",
            gmThreadId: thread ?? "thread-\(uid)",
            gmMessageId: "message-\(uid)",
            bodyPreview: preview,
            uidValidity: uidValidity,
            serverReceivedAt: now.addingTimeInterval(TimeInterval(-(minutesAgo ?? uid) * 60))
        )
        _ = try store.admit(header: header, account: account ?? ana)
    }
}
