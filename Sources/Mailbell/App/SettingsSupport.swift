import AppKit
import SwiftUI

struct OAuthSetupPanel: View {
    let details: String
    @State private var showsDetails = false

    var body: some View {
        Group {
            Label("Google OAuth setup required", systemImage: "key.fill")
                .foregroundStyle(.orange)

            Text(
                "Create your own Google Desktop OAuth client, set `MAILBELL_GOOGLE_CLIENT_ID` and "
                    + "`MAILBELL_GOOGLE_CLIENT_SECRET`, then rebuild or reinstall Mailbell."
            )
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)

            if let readmeURL = SetupGuide.readmeURL {
                Button("Open README") {
                    NSWorkspace.shared.open(readmeURL)
                }
            }

            Text("See README > Google Cloud Setup.")
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            DisclosureGroup("Details", isExpanded: $showsDetails) {
                Text(details)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
enum SettingsWindow {
    static func open(retryCount: Int = 3) {
        NSApp.activate(ignoringOtherApps: true)
        let didSend = NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        guard !didSend, retryCount > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            open(retryCount: retryCount - 1)
        }
    }

    static func openWhenReady() {
        DispatchQueue.main.async {
            open()
        }
    }
}
