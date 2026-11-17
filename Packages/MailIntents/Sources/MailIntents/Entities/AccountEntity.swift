public import AppIntents
import MailCore

/// A signed-in account, as Siri and Shortcuts see it.
@AppEntity(schema: .mail.account)
public struct AccountEntity {
    public static let defaultQuery = AccountQuery()

    public let id: String
    public var name: String
    public var emailAddress: String
    /// What the app calls the account (`Account.title`): its nickname, or its address.
    let title: String

    public var displayRepresentation: DisplayRepresentation {
        title == emailAddress
            ? DisplayRepresentation(title: "\(title)")
            : DisplayRepresentation(title: "\(title)", subtitle: "\(emailAddress)")
    }

    init(_ account: Account) {
        id = account.id.rawValue
        // Set before the schema's own properties: setting one of those reads `self`, so every plain stored property
        // has to be set first or the init doesn't compile.
        title = account.title
        // The reader's nickname for the account comes first, so "my Work account" finds it.
        name = account.nickname ?? account.name ?? account.email
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
