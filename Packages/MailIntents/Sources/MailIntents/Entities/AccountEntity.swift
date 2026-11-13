import AppIntents
import MailCore

/// A signed-in account, as Siri and Shortcuts see it.
@AppEntity(schema: .mail.account)
public struct AccountEntity {
    public static let defaultQuery = AccountQuery()

    public let id: String
    public var name: String
    public var emailAddress: String

    public var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(emailAddress)") }

    init(_ account: Account) {
        id = account.id.rawValue
        name = account.name ?? account.email
        emailAddress = account.email
    }

    var accountID: AccountID { AccountID(rawValue: id) }
}

public struct AccountQuery: EntityQuery {
    @Dependency private var host: any MailIntentsHost

    public init() {}

    public func entities(for identifiers: [String]) async throws -> [AccountEntity] {
        try Catalog(host: host).accounts().filter { identifiers.contains($0.id) }
    }

    public func suggestedEntities() async throws -> [AccountEntity] {
        try Catalog(host: host).accounts()
    }
}
