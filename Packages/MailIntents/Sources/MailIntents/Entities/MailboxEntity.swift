import AppIntents
import MailCore

/// One account's mailbox: a standard one or a label. The mail schema gives every mailbox an account, so the blended
/// Inbox is offered as each account's.
@AppEntity(schema: .mail.mailbox)
public struct MailboxEntity {
    public static let defaultQuery = MailboxQuery()

    public let id: String
    public var name: String
    public var account: AccountEntity

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(account.emailAddress)")
    }

    init(_ mailbox: NamedMailbox, account: AccountEntity) {
        id = EntityID.string(mailbox.mailbox, account: account.accountID)
        name = mailbox.name
        self.account = account
    }

    var mailbox: Mailbox? { EntityID.mailbox(id) }
}

public struct MailboxQuery: EntityStringQuery {
    @Dependency private var host: any MailIntentsHost

    public init() {}

    public func entities(for identifiers: [String]) async throws -> [MailboxEntity] {
        try Catalog(host: host).mailboxes().filter { identifiers.contains($0.id) }
    }

    public func entities(matching string: String) async throws -> [MailboxEntity] {
        try Catalog(host: host).mailboxes().filter { $0.name.localizedStandardContains(string) }
    }

    public func suggestedEntities() async throws -> [MailboxEntity] {
        try Catalog(host: host).mailboxes()
    }
}
