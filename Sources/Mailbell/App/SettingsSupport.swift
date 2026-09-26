import AppKit
import SwiftUI

/// Shown when the running build has no usable Google OAuth client. In a public
/// release this is a packaging defect, not something an end user can fix, so the
/// copy names it as a build problem and points at the issue tracker instead of
/// asking the user to create their own Google Cloud client.
struct BuildProblemPanel: View {
    let details: String
    @State private var showsDetails = false

    var body: some View {
        Label(SettingsCopy.BuildProblem.headline, systemImage: SettingsStatusTone.warning.systemImage)

        Text(SettingsCopy.BuildProblem.explanation)
        .foregroundStyle(.secondary)
        .textSelection(.enabled)

        Text(SettingsCopy.BuildProblem.nextStep)
        .foregroundStyle(.secondary)
        .textSelection(.enabled)

        Link(SettingsCopy.BuildProblem.reportAction, destination: ProjectLinks.issues)

        DisclosureGroup(SettingsCopy.BuildProblem.detailsDisclosure, isExpanded: $showsDetails) {
            Text(details)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }
}

enum SystemSettings {
    static func open() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }
}

@MainActor
enum SettingsWindowPresenter {
    static func bringToFront() {
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            for window in NSApp.windows where window.isVisible {
                window.makeKeyAndOrderFront(nil)
            }
        }
    }
}
