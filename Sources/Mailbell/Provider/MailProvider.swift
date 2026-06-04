import Foundation

struct ProviderCapabilities: Equatable {
    var supportsIdle: Bool
    var supportsThreadLink: Bool
}

protocol MailProvider {
    var id: MailProviderID { get }
    var displayName: String { get }
    var capabilities: ProviderCapabilities { get }
    var webmailURL: URL { get }
    func webmailURL(for header: MessageHeader) -> URL
}

struct GmailProvider: MailProvider {
    let id: MailProviderID = .gmail
    let displayName = "Google Gmail"
    let capabilities = ProviderCapabilities(supportsIdle: true, supportsThreadLink: true)
    let webmailURL = URL(string: "https://mail.google.com/")!

    func webmailURL(for header: MessageHeader) -> URL {
        guard let threadID = header.gmThreadId,
              let threadValue = UInt64(threadID, radix: 10) else {
            return webmailURL
        }
        let threadHex = String(threadValue, radix: 16)
        return URL(string: "https://mail.google.com/mail/u/0/#inbox/\(threadHex)") ?? webmailURL
    }
}

enum MailProviderRegistry {
    static func provider(for id: MailProviderID) -> MailProvider {
        switch id {
        case .gmail:
            return GmailProvider()
        }
    }
}
