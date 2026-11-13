import AppIntents
import MailCore

/// One message of a thread, as Siri and Shortcuts see it. Only cached messages are entities: the rest have no body
/// or recipients on the device yet.
@AppEntity(schema: .mail.message)
public struct MessageEntity {
    public static let defaultQuery = MessageQuery()

    public let id: String
    public var subject: String?
    public var body: String?
    public var sender: IntentPerson
    public var to: [IntentPerson]
    public var cc: [IntentPerson]
    public var bcc: [IntentPerson]
    public var dateSent: Date
    public var dateReceived: Date
    public var isRead: Bool
    public var isFlagged: Bool
    public var isJunk: Bool
    public var attachments: [IntentFile]
    public var mailbox: MailboxEntity
    public var account: AccountEntity
    public var category: MailCategoryEntity?
    /// The sender's name or address, for the subtitle.
    var senderName: String

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(subject ?? "")", subtitle: "\(senderName)")
    }

    init(_ message: Message, mailbox: MailboxEntity, account: AccountEntity) {
        id = EntityID.string(message.id, inThread: message.threadID)
        senderName = message.from.displayName
        subject = message.subject.isEmpty ? nil : message.subject
        body = Self.text(of: message.body)
        sender = IntentPerson(message.from)
        to = message.to.map(IntentPerson.init)
        cc = message.cc.map(IntentPerson.init)
        bcc = message.bcc.map(IntentPerson.init)
        dateSent = message.date
        dateReceived = message.date
        isRead = !message.isUnread
        isFlagged = message.labelIDs.contains(SystemLabel.starred)
        isJunk = message.labelIDs.contains(SystemLabel.spam)
        // Attachments are fetched when opened; the entity names none it can't hand over.
        attachments = []
        self.mailbox = mailbox
        self.account = account
        category = MailCategoryEntity(labels: message.labelIDs)
    }

    /// The body as plain text: the plain part, or else the HTML's text.
    private static func text(of body: MessageBody) -> String? {
        let text = body.plain.flatMap { $0.isEmpty ? nil : $0 } ?? body.html.map(HTMLEntities.plainText(fromHTML:))
        return text?.isEmpty == false ? text : nil
    }

    var threadID: ThreadSummary.ID? { EntityID.message(id)?.thread }
}

public struct MessageQuery: EntityStringQuery {
    @Dependency private var host: any MailIntentsHost

    public init() {}

    public func entities(for identifiers: [String]) async throws -> [MessageEntity] {
        try Catalog(host: host).messages(identifiers)
    }

    /// The cached messages of the conversations search finds.
    public func entities(matching string: String) async throws -> [MessageEntity] {
        try Catalog(host: host).threads(matching: string).flatMap(\.messages)
    }

    /// The cached messages of the newest conversations in the Inbox.
    public func suggestedEntities() async throws -> [MessageEntity] {
        try Catalog(host: host).recentThreads().flatMap(\.messages)
    }
}

extension IntentPerson {
    init(_ contact: Contact) {
        self.init(
            identifier: .applicationDefined(contact.address),
            name: contact.name.map { .displayName($0) } ?? .unknown,
            handle: IntentPerson.Handle(emailAddress: contact.address))
    }
}
