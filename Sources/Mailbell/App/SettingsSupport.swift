import AppKit
import SwiftUI

/// Shown when the running build has no usable Google OAuth client. In a public
/// release this is a packaging defect, not something an end user can fix, so the
/// copy names it as a build problem and points at the issue tracker instead of
/// asking the user to create their own Google Cloud client.
struct OAuthSetupPanel: View {
    let details: String
    @State private var showsDetails = false

    var body: some View {
        Label("This build is missing its Google OAuth configuration", systemImage: "exclamationmark.triangle.fill")

        Text(
            "Mailbell releases ship with the Google Desktop OAuth client already configured. "
                + "Seeing this means the build was packaged without it, which no setting can fix."
        )
        .foregroundStyle(.secondary)
        .textSelection(.enabled)

        Text(
            "If you downloaded this build from GitHub Releases, please report it. "
                + "If you built Mailbell yourself, set MAILBELL_GOOGLE_CLIENT_ID in .env and reinstall."
        )
        .foregroundStyle(.secondary)
        .textSelection(.enabled)

        Link("Report a Packaging Issue", destination: ProjectLinks.issues)

        DisclosureGroup("Build Details", isExpanded: $showsDetails) {
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
