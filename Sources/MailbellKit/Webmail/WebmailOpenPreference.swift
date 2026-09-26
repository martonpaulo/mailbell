import Foundation

public struct WebmailOpenPreference: Codable, Equatable, Sendable {
    public var browser: BrowserSelection
    public var chromeProfileDirectory: String?

    public init(browser: BrowserSelection, chromeProfileDirectory: String?) {
        self.browser = browser
        self.chromeProfileDirectory = chromeProfileDirectory
    }
}

public enum BrowserSelection: Codable, Equatable, Sendable {
    case systemDefault
    case application(bundleIdentifier: String, appPath: String)

    private enum CodingKeys: String, CodingKey {
        case kind
        case bundleIdentifier
        case appPath
    }

    private enum Kind: String, Codable {
        case systemDefault
        case application
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .systemDefault:
            self = .systemDefault
        case .application:
            self = try .application(
                bundleIdentifier: container.decode(String.self, forKey: .bundleIdentifier),
                appPath: container.decode(String.self, forKey: .appPath)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .systemDefault:
            try container.encode(Kind.systemDefault, forKey: .kind)
        case let .application(bundleIdentifier, appPath):
            try container.encode(Kind.application, forKey: .kind)
            try container.encode(bundleIdentifier, forKey: .bundleIdentifier)
            try container.encode(appPath, forKey: .appPath)
        }
    }
}

public struct BrowserCandidate: Identifiable, Equatable, Sendable {
    public static let systemDefaultID = "mailbell.systemDefault"

    public let id: String
    public let displayName: String
    public let bundleIdentifier: String?
    public let appURL: URL?
    public let supportsChromeProfiles: Bool

    public init(
        id: String,
        displayName: String,
        bundleIdentifier: String?,
        appURL: URL?,
        supportsChromeProfiles: Bool
    ) {
        self.id = id
        self.displayName = displayName
        self.bundleIdentifier = bundleIdentifier
        self.appURL = appURL
        self.supportsChromeProfiles = supportsChromeProfiles
    }

    public static let systemDefault = BrowserCandidate(
        id: systemDefaultID,
        displayName: String(localized: "System Default"),
        bundleIdentifier: nil,
        appURL: nil,
        supportsChromeProfiles: false
    )
}

public struct ChromeProfileCandidate: Identifiable, Equatable, Sendable {
    public let directory: String
    public let displayName: String
    let userName: String?

    public init(directory: String, displayName: String, userName: String?) {
        self.directory = directory
        self.displayName = displayName
        self.userName = userName
    }

    public var id: String {
        directory
    }

    public var pickerLabel: String {
        if let userName, !userName.isEmpty {
            return "\(displayName) (\(userName))"
        }
        return displayName
    }
}

public enum WebmailOpenOutcome: Equatable, Sendable {
    case opened
    case openedWithFallback(message: String)
    case failed(message: String)

    public var didOpen: Bool {
        switch self {
        case .opened, .openedWithFallback:
            true
        case .failed:
            false
        }
    }
}
