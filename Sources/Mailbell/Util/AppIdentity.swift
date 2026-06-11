import Foundation

enum AppIdentity {
    private static let localBundleIdentifier = "dev.mailbell.local"

    static var bundleIdentifier: String {
        let candidate = Bundle.main.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let candidate, !candidate.isEmpty else {
            return localBundleIdentifier
        }
        return candidate
    }

    static var keychainService: String {
        bundleIdentifier
    }

    static func dispatchQueueLabel(_ component: String) -> String {
        "\(bundleIdentifier).\(component)"
    }

    static var isPackagedApp: Bool {
        isPackagedApp(
            bundleURL: Bundle.main.bundleURL,
            executableURL: Bundle.main.executableURL,
            arguments: CommandLine.arguments
        )
    }

    static func isPackagedApp(bundleURL: URL, executableURL: URL?, arguments: [String]) -> Bool {
        if bundleURL.pathExtension == "app" {
            return true
        }

        let executablePath = executableURL?.standardizedFileURL.path
            ?? arguments.first
            ?? ""
        return executablePath.contains(".app/Contents/MacOS/")
    }
}
