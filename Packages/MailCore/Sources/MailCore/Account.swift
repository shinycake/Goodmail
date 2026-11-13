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

public struct Account: Identifiable, Equatable, Sendable {
    public let id: AccountID
    public var email: String
    public var color: AccountColor
    /// The name mail from this account is sent under, such as "Dana Levi". `nil` sends the address alone.
    public var name: String?

    public init(id: AccountID, email: String, color: AccountColor, name: String? = nil) {
        self.id = id
        self.email = email
        self.color = color
        self.name = name
    }

    /// What mail from this account says it is from.
    public var sender: Contact {
        Contact(name: name, address: email)
    }
}
