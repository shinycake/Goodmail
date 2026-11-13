import Foundation

public struct AccountID: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static func generate() -> AccountID {
        AccountID(rawValue: UUID().uuidString)
    }
}

/// The mail service an account signs in to, which decides the provider that talks to it.
public enum MailService: String, Codable, Sendable {
    case gmail
}

public struct Account: Identifiable, Equatable, Sendable {
    public let id: AccountID
    public var email: String
    public var color: AccountColor
    public let service: MailService

    public init(id: AccountID, email: String, color: AccountColor, service: MailService) {
        self.id = id
        self.email = email
        self.color = color
        self.service = service
    }
}
