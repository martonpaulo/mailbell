import AppKit
import SwiftUI

struct OAuthSetupPanel: View {
    let details: String
    @State private var showsDetails = false

    var body: some View {
        Group {
            Label("Google OAuth setup required", systemImage: "key.fill")

            Text(
                "Create your own Google Desktop OAuth client, set `MAILBELL_GOOGLE_CLIENT_ID`, "
                    + "then rebuild or reinstall Mailbell. `MAILBELL_GOOGLE_CLIENT_SECRET` is optional."
            )
            .foregroundStyle(.secondary)
            .textSelection(.enabled)

            if let readmeURL = SetupGuide.readmeURL {
                Button("Open Setup Guide") {
                    NSWorkspace.shared.open(readmeURL)
                }
            }

            Text("See the Google Cloud Setup section in README.")
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            DisclosureGroup("Setup Details", isExpanded: $showsDetails) {
                Text(details)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }
}

enum SetupGuide {
    static var readmeURL: URL? {
        var candidates = [
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("README.md"),
            Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("README.md")
        ]
        if let bundledURL = Bundle.main.url(forResource: "README", withExtension: "md") {
            candidates.append(bundledURL)
        }

        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
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
