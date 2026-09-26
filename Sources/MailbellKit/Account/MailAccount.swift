import Foundation

public enum MailProviderID: String, Codable, CaseIterable, Sendable {
    case gmail

    var displayName: String {
        switch self {
        case .gmail:
            "Gmail"
        }
    }
}

public struct MailAccount: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var providerID: MailProviderID
    public var email: String
    var displayName: String?
    public var isEnabled: Bool
    var createdAt: Date
    public var webmailOpenPreference: WebmailOpenPreference?

    public init(
        id: UUID = UUID(),
        providerID: MailProviderID,
        email: String,
        displayName: String? = nil,
        isEnabled: Bool = true,
        createdAt: Date = Date(),
        webmailOpenPreference: WebmailOpenPreference? = nil
    ) {
        self.id = id
        self.providerID = providerID
        self.email = email
        self.displayName = displayName
        self.isEnabled = isEnabled
        self.createdAt = createdAt
        self.webmailOpenPreference = webmailOpenPreference
    }
}

public struct AccountRuntimeState: Identifiable, Equatable, Sendable {
    public var account: MailAccount
    public var status: MonitorStatus
    public var lastError: String?
    public var webmailOpenError: String?

    public init(
        account: MailAccount,
        status: MonitorStatus,
        lastError: String? = nil,
        webmailOpenError: String? = nil
    ) {
        self.account = account
        self.status = status
        self.lastError = lastError
        self.webmailOpenError = webmailOpenError
    }

    public var id: UUID {
        account.id
    }
}
