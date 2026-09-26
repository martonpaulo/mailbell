import MailbellKit
import SwiftUI

/// Renders `MenuPresentation` as the native menu of the `MenuBarExtra`. It
/// decides nothing: order, copy, visibility and state all come from the
/// presentation (Decided on #69). No custom views are embedded, so every item
/// is a native `NSMenuItem`: plain Text is a disabled item, a second Text in a
/// label is the item's subtitle, and `Section` is a native section header.
struct MenuContent: View {
    @Environment(\.openSettings) private var openSettings
    let appState: AppState

    var body: some View {
        let menu = appState.menuPresentation()

        if !menu.problems.isEmpty {
            ForEach(menu.problems) { problem in
                problemItem(problem)
            }
            Divider()
        }

        switch menu.body {
        case .noAccount(let message, let addAccount):
            Text(message)
            commandButton(addAccount)
        case .queue(let queue):
            queueItems(queue)
        }

        Divider()

        if !menu.accounts.isEmpty {
            Menu(MenuCopy.accountsMenuTitle) {
                ForEach(menu.accounts) { account in
                    accountMenu(account)
                }
            }
        }
        commandButtons(menu.footer)
    }

    // MARK: - Problems

    @ViewBuilder
    private func problemItem(_ problem: MenuProblem) -> some View {
        Button {
        } label: {
            Label {
                Text(problem.title)
                if let subtitle = problem.subtitle {
                    Text(subtitle)
                }
            } icon: {
                Image(systemName: MenuProblem.systemImage)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Token.Palette.alertGlyph, Token.Palette.alertFill)
            }
        }
        .disabled(true)
        if let command = problem.command {
            commandButton(command)
        }
    }

    // MARK: - Queue

    @ViewBuilder
    private func queueItems(_ queue: MenuQueue) -> some View {
        if let header = queue.header {
            Section(header) {
                queueCommands(queue)
            }
        } else {
            if let emptyText = queue.emptyText {
                Text(emptyText)
            }
            queueCommands(queue)
        }

        if !queue.groups.isEmpty {
            Divider()
        }
        ForEach(queue.groups) { group in
            if let header = group.header {
                Section(header) {
                    groupItems(group)
                }
            } else {
                groupItems(group)
            }
        }
    }

    @ViewBuilder
    private func queueCommands(_ queue: MenuQueue) -> some View {
        if let lastAction = queue.lastAction {
            Text(lastAction)
        }
        if let bulk = queue.bulk {
            Menu(bulk.title) {
                Text(bulk.scope)
                Divider()
                commandButtons(bulk.commands)
            }
        }
        commandButton(queue.checkForNewMail)
    }

    @ViewBuilder
    private func groupItems(_ group: MenuGroup) -> some View {
        ForEach(group.rows) { row in
            rowMenu(row)
        }
        if let overflow = group.overflow {
            Text(overflow)
        }
    }

    private func rowMenu(_ row: MenuRow) -> some View {
        Menu {
            commandButtons(row.commands)
            Divider()
            Button {
            } label: {
                Text(row.sender)
                Text(row.recipient)
            }
            .disabled(true)
            ForEach(Array(row.subjectLines.enumerated()), id: \.offset) { _, line in
                Text(line)
            }
            ForEach(Array(row.previewLines.enumerated()), id: \.offset) { _, line in
                Text(line)
            }
        } label: {
            Text(row.title)
            Text(row.subtitle)
        }
    }

    // MARK: - Accounts

    private func accountMenu(_ account: MenuAccount) -> some View {
        Menu {
            ForEach(Array(account.details.enumerated()), id: \.offset) { _, detail in
                Text(detail)
            }
            Divider()
            commandButtons(account.commands)
        } label: {
            Label(account.title, systemImage: account.systemImage)
        }
    }

    // MARK: - Commands

    private func commandButtons(_ commands: [MenuCommand]) -> some View {
        ForEach(Array(commands.enumerated()), id: \.offset) { _, command in
            commandButton(command)
        }
    }

    @ViewBuilder
    private func commandButton(_ command: MenuCommand) -> some View {
        let button = Button(command.title) {
            appState.perform(command.action) { openSettings() }
        }
        .disabled(!command.isEnabled)
        if let key = command.keyEquivalent {
            button.keyboardShortcut(KeyEquivalent(key), modifiers: .command)
        } else {
            button
        }
    }
}
