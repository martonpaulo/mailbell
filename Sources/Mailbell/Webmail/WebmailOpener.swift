import AppKit
import Foundation

@MainActor
enum WebmailOpener {
    static func open(
        url: URL,
        account: MailAccount?,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default,
        workspace: NSWorkspace = .shared
    ) async -> WebmailOpenOutcome {
        let preference = account?.webmailOpenPreference
        guard let preference else {
            return openWithSystemDefault(url, workspace: workspace)
        }

        switch preference.browser {
        case .systemDefault:
            return openWithSystemDefault(url, workspace: workspace)
        case let .application(bundleIdentifier, appPath):
            let appURL = URL(fileURLWithPath: appPath)
            guard fileManager.fileExists(atPath: appPath) else {
                let outcome = openWithSystemDefault(url, workspace: workspace)
                return mergeFallback(
                    outcome,
                    message: "Selected browser is no longer available."
                )
            }

            if bundleIdentifier == BrowserRegistry.chromeBundleID,
               let profileDirectory = preference.chromeProfileDirectory,
               !profileDirectory.isEmpty {
                return await openChrome(
                    url: url,
                    appURL: appURL,
                    profileDirectory: profileDirectory,
                    context: OpenContext(
                        homeDirectory: homeDirectory,
                        fileManager: fileManager,
                        workspace: workspace
                    )
                )
            }

            return await openWithApplication(url: url, appURL: appURL, workspace: workspace)
        }
    }

    private static func openChrome(
        url: URL,
        appURL: URL,
        profileDirectory: String,
        context: OpenContext
    ) async -> WebmailOpenOutcome {
        guard ChromeProfileStore.profileExists(
            directory: profileDirectory,
            homeDirectory: context.homeDirectory,
            fileManager: context.fileManager
        )
        else {
            return await mergeFallback(
                openWithApplication(url: url, appURL: appURL, workspace: context.workspace),
                message: "Selected Chrome profile is no longer available."
            )
        }

        let executable = chromeExecutableURL(appURL: appURL)
        guard context.fileManager.fileExists(atPath: executable.path) else {
            return await mergeFallback(
                openWithApplication(url: url, appURL: appURL, workspace: context.workspace),
                message: "Could not open Gmail with the selected Chrome profile."
            )
        }

        let process = Process()
        process.executableURL = executable
        process.arguments = ["--profile-directory=\(profileDirectory)", url.absoluteString]
        do {
            try process.run()
            return .opened
        } catch {
            return await mergeFallback(
                openWithApplication(url: url, appURL: appURL, workspace: context.workspace),
                message: "Could not open Gmail with the selected Chrome profile."
            )
        }
    }

    private static func chromeExecutableURL(appURL: URL) -> URL {
        appURL.appendingPathComponent("Contents/MacOS/Google Chrome")
    }

    private static func openWithApplication(
        url: URL,
        appURL: URL,
        workspace: NSWorkspace
    ) async -> WebmailOpenOutcome {
        await withCheckedContinuation { continuation in
            let configuration = NSWorkspace.OpenConfiguration()
            workspace.open([url], withApplicationAt: appURL, configuration: configuration) { _, error in
                Task { @MainActor in
                    let outcome: WebmailOpenOutcome = if error == nil {
                        .opened
                    } else {
                        openWithSystemDefault(
                            url,
                            workspace: .shared,
                            fallbackMessage: "Could not open Gmail with the selected browser."
                        )
                    }
                    continuation.resume(returning: outcome)
                }
            }
        }
    }

    private static func openWithSystemDefault(
        _ url: URL,
        workspace: NSWorkspace,
        fallbackMessage: String? = nil
    ) -> WebmailOpenOutcome {
        if workspace.open(url) {
            if let fallbackMessage {
                return .openedWithFallback(message: fallbackMessage)
            }
            return .opened
        }
        if let fallbackMessage {
            return .failed(message: fallbackMessage)
        }
        return .failed(message: "Could not open Gmail.")
    }

    private static func mergeFallback(_ outcome: WebmailOpenOutcome, message: String) -> WebmailOpenOutcome {
        switch outcome {
        case .opened:
            .openedWithFallback(message: message)
        case let .openedWithFallback(existing):
            .openedWithFallback(message: "\(message) \(existing)")
        case .failed:
            .failed(message: message)
        }
    }

    private struct OpenContext {
        let homeDirectory: URL
        let fileManager: FileManager
        let workspace: NSWorkspace
    }
}
