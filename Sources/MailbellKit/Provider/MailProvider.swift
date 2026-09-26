import Foundation

public struct ProviderCapabilities: Equatable, Sendable {
    public var supportsIdle: Bool
    public var supportsThreadLink: Bool
}

public protocol MailProvider {
    var id: MailProviderID { get }
    var displayName: String { get }
    var capabilities: ProviderCapabilities { get }
    var webmailURL: URL { get }
    func webmailURL(for account: MailAccount?) -> URL
    func webmailURL(for header: MessageHeader) -> URL
    func webmailURL(for header: MessageHeader, account: MailAccount?) -> URL
}

public struct GmailProvider: MailProvider, Sendable {
    public init() {}

    public let id: MailProviderID = .gmail
    public var displayName: String {
        id.displayName
    }

    public let capabilities = ProviderCapabilities(supportsIdle: true, supportsThreadLink: true)
    public let webmailURL = URL(string: "https://mail.google.com/")!

    public func webmailURL(for _: MailAccount?) -> URL {
        webmailURL
    }

    public func webmailURL(for header: MessageHeader) -> URL {
        webmailURL(for: header, account: nil)
    }

    public func webmailURL(for header: MessageHeader, account: MailAccount?) -> URL {
        guard let threadID = header.gmThreadId,
              let threadValue = UInt64(threadID, radix: 10)
        else {
            return webmailURL(for: account)
        }
        let threadHex = String(threadValue, radix: 16)
        return URL(string: "https://mail.google.com/mail/#inbox/\(threadHex)") ?? webmailURL(for: account)
    }
}

public enum MailProviderRegistry {
    public static func provider(for id: MailProviderID) -> MailProvider {
        switch id {
        case .gmail:
            GmailProvider()
        }
    }
}
