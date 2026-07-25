@testable import mailbell
import XCTest

/// Guards the control-usage rules that a compiling build cannot enforce: the
/// panes are SwiftUI code, so these assert the source shape instead.
final class SettingsControlSemanticsTests: XCTestCase {
    func testNoToggleLabelInvertsWithItsOwnState() throws {
        // A toggle labelled "Disable Account" reads as its own opposite the
        // moment it is on. Labels must describe the enabled state instead.
        for source in try paneSources() {
            for line in source.code {
                if line.contains("Toggle(") {
                    XCTAssertFalse(
                        line.contains("Title(for:") || line.contains("accountEnabledTitle"),
                        "\(source.name): toggle label must be a fixed string, not derived from its own value"
                    )
                }
                XCTAssertFalse(
                    line.contains("\"Disable "),
                    "\(source.name): a toggle or its copy must not be labelled with the inverse action"
                )
            }
        }
    }

    func testNoButtonIsWrappedInALabelThatRestatesIt() throws {
        // LabeledContent means label to value. Wrapping a button in one
        // produces rows like "Remove Account: Remove", which read as noise.
        for source in try paneSources() {
            let lines = source.code
            for (index, line) in lines.enumerated() where line.contains("LabeledContent(") {
                let following = lines[index ..< min(index + 3, lines.count)].joined(separator: " ")
                XCTAssertFalse(
                    following.contains("Button("),
                    "\(source.name):\(index + 1): use a plain Button; LabeledContent is for label to value"
                )
            }
        }
    }

    func testDestructiveActionsUseTheRoleRatherThanManualColor() throws {
        for source in try paneSources() {
            XCTAssertFalse(
                source.contents.contains("foregroundStyle(.red)"),
                "\(source.name): use Button(role: .destructive) instead of colouring a control red"
            )
        }
    }

    func testEveryPaneExplainsItselfWithoutRepeatingTheTabName() throws {
        // A section header that restates the tab it lives in is wasted space.
        for source in try paneSources() where source.name == "SettingsAboutPane.swift" {
            XCTAssertFalse(
                source.contents.contains("Text(\"About\")"),
                "\(source.name): drop the section header that repeats the tab name"
            )
        }
    }

    private struct PaneSource {
        let name: String
        let contents: String

        /// Source lines with comments dropped, so a rule never trips on prose
        /// that merely names the thing it forbids.
        var code: [String] {
            contents
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { String($0).trimmingCharacters(in: .whitespaces) }
                .filter { !$0.hasPrefix("//") }
        }
    }

    /// Discovered rather than listed, so adding or folding away a pane cannot
    /// silently drop it out of these rules.
    private func paneSources() throws -> [PaneSource] {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/Mailbell/App")
        let names = try FileManager.default.contentsOfDirectory(atPath: root.path)
            .filter { $0.hasPrefix("Settings") && $0.hasSuffix("Pane.swift") }
            .sorted()
        XCTAssertFalse(names.isEmpty, "no Settings pane sources found")
        return try names.map { name in
            try PaneSource(
                name: name,
                contents: String(contentsOf: root.appendingPathComponent(name), encoding: .utf8)
            )
        }
    }
}
