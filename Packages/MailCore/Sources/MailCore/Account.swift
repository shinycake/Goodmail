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

public struct Account: Identifiable, Hashable, Sendable {
    public let id: AccountID
    public var email: String
    public var color: AccountColor

    public init(id: AccountID, email: String, color: AccountColor) {
        self.id = id
        self.email = email
        self.color = color
    }
}
