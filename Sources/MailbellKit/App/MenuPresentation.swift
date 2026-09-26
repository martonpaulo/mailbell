import Foundation

/// Everything the menu bar dropdown shows, decided in one pure place so the
/// SwiftUI menu only renders it (Decided on #69).
///
/// The order is fixed: problem rows, then either the no-account commands or
/// the review queue (header, bulk submenu, Check for New Mail, one group per
/// account), then the footer (Accounts, Check for Updates…, Settings…, Quit).
public struct MenuPresentation: Equatable, Sendable {
    /// Row titles, subtitles and preview lines are cut here: a native menu is
    /// as wide as its longest item.
    public static let lineLimit = 60
    /// Preview lines in a row's submenu, each a single disabled item.
    public static let previewLineCount = 3

    public let problems: [MenuProblem]
    public let body: Body
    public let accounts: [MenuAccount]
    public let footer: [MenuCommand]

    public enum Body: Equatable, Sendable {
        case noAccount(message: String, addAccount: MenuCommand)
        case queue(MenuQueue)
    }

    /// The state the presentation is derived from. Every field is a value the
    /// app already holds; nothing here is stored twice.
    public struct Input: Sendable {
        public var accounts: [AccountRuntimeState] = []
        public var shownItems: [ReviewItem] = []
        /// Retained messages in each shown item's conversation, by item id.
        public var conversationSizes: [String: Int] = [:]
        public var hiddenConversationCounts: [UUID: Int] = [:]
        public var reach = ReviewReach(messages: 0, conversations: 0)
        public var canMarkAllAsRead = false
        public var isMarkingAllAsRead = false
        public var canCheckForNewMail = false
        public var isAuthorizing = false
        public var notificationsAreOff = false
        public var buildProblem: BuildProblem?
        public var signInError: String?
        public var accountStoreError: String?
        public var lastActionMessage: String?
        public var isUpdaterAvailable = false
        public var now = Date()
        public var calendar = Calendar.autoupdatingCurrent
        public var locale = Locale.autoupdatingCurrent

        public init() {}
    }

    /// The build has no usable OAuth client. The headline is Settings' own, so
    /// both surfaces name the problem with one string.
    public struct BuildProblem: Equatable, Sendable {
        public let headline: String
        public let details: String

        public init(headline: String, details: String) {
            self.headline = headline
            self.details = details
        }
    }

    public init(_ input: Input) {
        problems = Self.problems(input)
        accounts = input.accounts.map { Self.account($0, input: input) }
        if input.accounts.isEmpty {
            body = .noAccount(
                message: MenuCopy.noAccount,
                addAccount: MenuCommand(
                    title: input.isAuthorizing ? MenuCopy.signingIn : MenuCopy.addAccount,
                    action: .addAccount,
                    isEnabled: input.buildProblem == nil && !input.isAuthorizing
                )
            )
            footer = Self.footer(showsCheckForUpdates: false)
        } else {
            body = .queue(Self.queue(input))
            footer = Self.footer(showsCheckForUpdates: input.isUpdaterAvailable)
        }
    }
}

// MARK: - Output types

/// One menu command. The renderer maps `action` to the app; it decides nothing.
public struct MenuCommand: Equatable, Sendable {
    public enum Action: Equatable, Sendable {
        case addAccount
        case signInAgain(accountID: UUID)
        case reconnect(accountID: UUID)
        case resumeWatching(accountID: UUID)
        case openSystemSettings
        case checkForNewMail
        case openGmail(accountID: UUID)
        case open(itemID: String)
        case markAsRead(itemID: String)
        case dismiss(itemID: String)
        /// Carries its confirmation when the action reaches messages the menu
        /// does not show; the renderer asks before it acts.
        case markAllAsRead(confirmation: MenuConfirmation?)
        case dismissAll
        case checkForUpdates
        case settings
        case quit
    }

    public let title: String
    public let action: Action
    public let isEnabled: Bool
    /// A native key equivalent with the Command modifier, such as "," or "q".
    public let keyEquivalent: Character?

    public init(title: String, action: Action, isEnabled: Bool = true, keyEquivalent: Character? = nil) {
        self.title = title
        self.action = action
        self.isEnabled = isEnabled
        self.keyEquivalent = keyEquivalent
    }
}

public struct MenuConfirmation: Equatable, Sendable {
    public let title: String
    public let message: String
    public let confirm: String
    public let cancel: String
}

/// Something that stops Mailbell from doing its job until the user acts: a
/// disabled item with an alert symbol, a title and a subtitle, then its fix.
public struct MenuProblem: Equatable, Sendable, Identifiable {
    public static let systemImage = "exclamationmark.triangle.fill"

    public let id: String
    public let title: String
    public let subtitle: String?
    public let command: MenuCommand?
}

public struct MenuQueue: Equatable, Sendable {
    /// The section header; nil when the queue is empty and `emptyText` shows.
    public let header: String?
    public let emptyText: String?
    public let lastAction: String?
    public let bulk: MenuBulk?
    public let checkForNewMail: MenuCommand
    public let groups: [MenuGroup]
}

public struct MenuBulk: Equatable, Sendable {
    public let title: String
    public let scope: String
    public let commands: [MenuCommand]
}

/// One account's rows. The header names the account only when there is more
/// than one account to tell apart.
public struct MenuGroup: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let header: String?
    public let rows: [MenuRow]
    public let overflow: String?
}

public struct MenuRow: Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let commands: [MenuCommand]
    public let sender: String
    public let recipient: String
    /// The full subject, only when the row had to cut it.
    public let subjectLines: [String]
    public let previewLines: [String]
}

/// An account in the Accounts submenu: its address, then its state and fixes.
public struct MenuAccount: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let title: String
    public let systemImage: String
    public let details: [String]
    public let commands: [MenuCommand]
}

// MARK: - Derivation

extension MenuPresentation {
    /// Confirmation only when the action reaches messages the menu does not
    /// show; each visible row stands for one message.
    public static func bulkConfirmation(reach: ReviewReach, visibleRows: Int) -> MenuConfirmation? {
        let hiddenMessages = reach.messages - visibleRows
        guard hiddenMessages > 0 else { return nil }
        return MenuConfirmation(
            title: MenuCopy.Confirmation.title(messages: reach.messages),
            message: MenuCopy.Confirmation.message(hiddenMessages: hiddenMessages),
            confirm: MenuCopy.Confirmation.confirm,
            cancel: MenuCopy.Confirmation.cancel
        )
    }

    /// Cuts a single-line item to `limit` characters, ending with "…".
    public static func truncated(_ text: String, limit: Int = lineLimit) -> String {
        let collapsed = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard collapsed.count > limit else { return collapsed }
        let cut = collapsed.prefix(limit - 1).trimmingCharacters(in: .whitespaces)
        return cut + "…"
    }

    /// Word-wraps text into lines of at most `width` characters. With a
    /// `maxLines`, the last line ends with "…" when text remains.
    public static func wrapped(_ text: String, width: Int = lineLimit, maxLines: Int? = nil) -> [String] {
        var lines: [String] = []
        var current = ""
        for word in text.split(whereSeparator: \.isWhitespace).map(String.init) {
            let candidate = current.isEmpty ? word : current + " " + word
            if candidate.count <= width {
                current = candidate
                continue
            }
            if !current.isEmpty {
                lines.append(current)
            }
            current = word.count > width ? truncated(word, limit: width) : word
        }
        if !current.isEmpty {
            lines.append(current)
        }
        guard let maxLines, lines.count > maxLines else { return lines }
        var kept = Array(lines.prefix(maxLines))
        let last = kept[maxLines - 1]
        kept[maxLines - 1] =
            last.count < width ? last + "…" : last.prefix(width - 1).trimmingCharacters(in: .whitespaces) + "…"
        return kept
    }

    /// When a row's message arrived, as short as the row allows: the time
    /// today, "Yesterday", the weekday within a week, then the date.
    public static func rowTime(
        for date: Date,
        now: Date,
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        if calendar.isDate(date, inSameDayAs: now) {
            formatter.dateStyle = .none
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }
        let days =
            calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now))
            .day ?? 0
        if days == 1 {
            return MenuCopy.yesterday
        }
        if (2...6).contains(days) {
            formatter.setLocalizedDateFormatFromTemplate("EEEE")
        } else if calendar.isDate(date, equalTo: now, toGranularity: .year) {
            formatter.setLocalizedDateFormatFromTemplate("MMMd")
        } else {
            formatter.setLocalizedDateFormatFromTemplate("yMMMd")
        }
        return formatter.string(from: date)
    }

    static func problems(_ input: Input) -> [MenuProblem] {
        var problems: [MenuProblem] = []
        if let buildProblem = input.buildProblem {
            problems.append(
                MenuProblem(
                    id: "build",
                    title: buildProblem.headline,
                    subtitle: truncated(buildProblem.details),
                    command: nil
                ))
        }
        if let accountStoreError = input.accountStoreError {
            problems.append(MenuProblem(id: "accountStore", title: accountStoreError, subtitle: nil, command: nil))
        }
        if let signInError = input.signInError {
            problems.append(MenuProblem(id: "signIn", title: signInError, subtitle: nil, command: nil))
        }
        for state in input.accounts where state.account.isEnabled {
            if let problem = accountProblem(state, input: input) {
                problems.append(problem)
            }
        }
        if input.notificationsAreOff {
            problems.append(
                MenuProblem(
                    id: "notifications",
                    title: MenuCopy.notificationsOff,
                    subtitle: MenuCopy.notificationsOffDetail,
                    command: MenuCommand(title: MenuCopy.openSystemSettings, action: .openSystemSettings)
                ))
        }
        return problems
    }

    private static func accountProblem(_ state: AccountRuntimeState, input: Input) -> MenuProblem? {
        let address = state.account.email
        switch state.status {
        case .signInRequired:
            return MenuProblem(
                id: "account.\(state.id)",
                title: MenuCopy.needsSignIn(address),
                subtitle: MenuCopy.needsSignInDetail,
                command: recoveryCommand(.signInAgain, accountID: state.id, input: input)
            )
        case .error:
            return MenuProblem(
                id: "account.\(state.id)",
                title: MenuCopy.cantConnect(address),
                subtitle: state.lastError.map { truncated($0) },
                command: recoveryCommand(.reconnect, accountID: state.id, input: input)
            )
        case .signedOut, .connecting, .connected, .reconnecting:
            return nil
        }
    }

    private static func recoveryCommand(
        _ action: AccountRecoveryAction,
        accountID: UUID,
        input: Input
    ) -> MenuCommand {
        let menuAction: MenuCommand.Action =
            switch action {
            case .enable: .resumeWatching(accountID: accountID)
            case .reconnect: .reconnect(accountID: accountID)
            case .signInAgain: .signInAgain(accountID: accountID)
            }
        return MenuCommand(
            title: action.title,
            action: menuAction,
            isEnabled: !(action.requiresAuthorizationSlot && input.isAuthorizing)
        )
    }

    static func queue(_ input: Input) -> MenuQueue {
        let count = input.shownItems.count
        let isEmpty = count == 0
        return MenuQueue(
            header: isEmpty ? nil : MenuCopy.toReview(count),
            emptyText: isEmpty ? MenuCopy.toReview(0) : nil,
            lastAction: input.lastActionMessage,
            bulk: isEmpty ? nil : bulk(input),
            checkForNewMail: MenuCommand(
                title: MenuCopy.checkForNewMail,
                action: .checkForNewMail,
                isEnabled: input.canCheckForNewMail
            ),
            groups: groups(input)
        )
    }

    private static func bulk(_ input: Input) -> MenuBulk {
        let confirmation = bulkConfirmation(reach: input.reach, visibleRows: input.shownItems.count)
        let markTitle: String =
            if input.isMarkingAllAsRead {
                MenuCopy.markingAllAsRead
            } else if confirmation != nil {
                MenuCopy.markAllAsReadConfirming
            } else {
                MenuCopy.markAllAsRead
            }
        return MenuBulk(
            title: MenuCopy.bulkMenuTitle,
            scope: MenuCopy.bulkScope(messages: input.reach.messages, conversations: input.reach.conversations),
            commands: [
                MenuCommand(
                    title: markTitle,
                    action: .markAllAsRead(confirmation: confirmation),
                    isEnabled: input.canMarkAllAsRead && !input.isMarkingAllAsRead
                ),
                MenuCommand(title: MenuCopy.dismissAll, action: .dismissAll, isEnabled: !input.isMarkingAllAsRead),
            ]
        )
    }

    private static func groups(_ input: Input) -> [MenuGroup] {
        let showsHeaders = input.accounts.count > 1
        return input.accounts.compactMap { state in
            let items = input.shownItems.filter { $0.accountID == state.id }
            guard !items.isEmpty else { return nil }
            return MenuGroup(
                id: state.id,
                header: showsHeaders ? state.account.email : nil,
                rows: items.map { row($0, input: input) },
                overflow: MenuCopy.overflowNotice(hiddenConversations: input.hiddenConversationCounts[state.id] ?? 0)
            )
        }
    }

    static func row(_ item: ReviewItem, input: Input) -> MenuRow {
        let identity = EmailHeaderFormatter.senderIdentity(from: item.sender)
        let messages = input.conversationSizes[item.id] ?? 1
        let name = messages > 1 ? MenuCopy.sender(identity.name, messages: messages) : identity.name
        let subject = truncated(item.subject)
        let subtitle =
            item.serverReceivedAt.map { date in
                MenuCopy.rowSubtitle(
                    subject: subject,
                    time: rowTime(for: date, now: input.now, calendar: input.calendar, locale: input.locale)
                )
            } ?? subject

        var commands = [MenuCommand(title: MenuCopy.openInGmail, action: .open(itemID: item.id))]
        // A row that cannot be marked hides the command rather than showing it
        // disabled with no reason.
        if item.canMarkAsRead {
            commands.append(MenuCommand(title: MenuCopy.markAsRead, action: .markAsRead(itemID: item.id)))
        }
        commands.append(MenuCommand(title: MenuCopy.dismiss, action: .dismiss(itemID: item.id)))

        let sender =
            if let address = identity.address, address != identity.name {
                MenuCopy.sender(identity.name, address: address)
            } else {
                identity.name
            }
        let fullSubject = item.subject.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return MenuRow(
            id: item.id,
            title: truncated(name),
            subtitle: subtitle,
            commands: commands,
            sender: truncated(sender),
            recipient: MenuCopy.recipient(item.accountEmail, time: item.timeText),
            subjectLines: subject == fullSubject ? [] : wrapped(fullSubject),
            previewLines: wrapped(item.bodyPreviewLines.joined(separator: " "), maxLines: previewLineCount)
        )
    }

    static func account(_ state: AccountRuntimeState, input: Input) -> MenuAccount {
        var details = [AccountPresentation.statusText(for: state)]
        if state.account.isEnabled, let error = state.lastError {
            details.append(truncated(error))
        }
        details.append(MenuCopy.toReview(input.shownItems.count { $0.accountID == state.id }))
        if let webmailError = state.webmailOpenError {
            details.append(truncated(webmailError))
        }
        var commands = [MenuCommand(title: MenuCopy.openGmail, action: .openGmail(accountID: state.id))]
        if let recovery = AccountRecoveryAction.needed(for: state) {
            commands.append(recoveryCommand(recovery, accountID: state.id, input: input))
        }
        return MenuAccount(
            id: state.id,
            title: state.account.email,
            systemImage: AccountPresentation.menuIconSystemName(for: state),
            details: details,
            commands: commands
        )
    }

    static func footer(showsCheckForUpdates: Bool) -> [MenuCommand] {
        var commands: [MenuCommand] = []
        // A development build has no updater: hide the command rather than
        // offer one that does nothing.
        if showsCheckForUpdates {
            commands.append(MenuCommand(title: MenuCopy.checkForUpdates, action: .checkForUpdates))
        }
        commands.append(MenuCommand(title: MenuCopy.settings, action: .settings, keyEquivalent: ","))
        commands.append(MenuCommand(title: MenuCopy.quit, action: .quit, keyEquivalent: "q"))
        return commands
    }
}
