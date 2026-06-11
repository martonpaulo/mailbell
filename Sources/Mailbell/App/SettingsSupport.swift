import AppKit
import SwiftUI

struct OAuthSetupPanel: View {
    let details: String
    @State private var showsDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Google OAuth setup required", systemImage: "key.fill")
                .font(.headline)
                .foregroundStyle(.orange)

            Text(
                "Create your own Google Desktop OAuth client, set `MAILBELL_GOOGLE_CLIENT_ID` and "
                    + "`MAILBELL_GOOGLE_CLIENT_SECRET`, then rebuild or reinstall Mailbell."
            )
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                if let readmeURL = SetupGuide.readmeURL {
                    Button("Open README") {
                        NSWorkspace.shared.open(readmeURL)
                    }
                }
                Text("See README > Google Cloud Setup.")
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            DisclosureGroup("Details", isExpanded: $showsDetails) {
                Text(details)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
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

enum SettingsFormMetrics {
    static let labelWidth: CGFloat = 104
}

struct SettingsFieldRow<Content: View>: View {
    private let title: String
    private let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        GridRow {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: SettingsFormMetrics.labelWidth, alignment: .trailing)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct SettingsMessageRow: View {
    let message: String

    var body: some View {
        GridRow {
            Color.clear
                .frame(width: SettingsFormMetrics.labelWidth)
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
