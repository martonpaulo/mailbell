import Foundation

public enum AppIdentity {
    private static let localBundleIdentifier = "dev.mailbell.local"

    public static var bundleIdentifier: String {
        let candidate = Bundle.main.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let candidate, !candidate.isEmpty else {
            return localBundleIdentifier
        }
        return candidate
    }

    public static var keychainService: String {
        bundleIdentifier
    }

    public static func dispatchQueueLabel(_ component: String) -> String {
        "\(bundleIdentifier).\(component)"
    }

    public static var isPackagedApp: Bool {
        isPackagedApp(
            bundleURL: Bundle.main.bundleURL,
            executableURL: Bundle.main.executableURL,
            arguments: CommandLine.arguments
        )
    }

    public static func isPackagedApp(bundleURL: URL, executableURL: URL?, arguments: [String]) -> Bool {
        if bundleURL.pathExtension == "app" {
            return true
        }

        let executablePath =
            executableURL?.standardizedFileURL.path
            ?? arguments.first
            ?? ""
        return executablePath.contains(".app/Contents/MacOS/")
    }
}
