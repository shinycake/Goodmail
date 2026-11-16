public import AppIntents
public import CoreSpotlight
public import MailCore

/// A conversation, as Siri, Shortcuts and Spotlight see it, with every fact its list row knows for Find and Filter.
@AppEntity(schema: .mail.thread)
public struct ThreadEntity {
    public static let defaultQuery = ThreadQuery()

    public let id: String
    public var title: String
    public var description: String?
    /// The messages cached on the device, oldest first. A thread only listed so far has none yet.
    public var messages: [MessageEntity]

    @Property(title: "Sender Name")
    public var senderName: String
    @Property(title: "Sender Address")
    public var senderAddress: String
    @Property(title: "Sender Domain")
    public var senderDomain: String
    /// The latest message's date, which Spotlight sorts by.
    @Property(title: "Date")
    public var date: Date
    @Property(title: "Number of Messages")
    public var messageCount: Int
    /// Every label and mailbox it's in, as Inbox, Starred or Receipts.
    @Property(title: "Labels")
    public var labels: [String]
    @Property(title: "Account Address")
    public var accountAddress: String
    @Property(title: "Is Unread")
    public var isUnread: Bool
    @Property(title: "Is Starred")
    public var isStarred: Bool
    @Property(title: "Is Important")
    public var isImportant: Bool
    @Property(title: "Is in Inbox")
    public var isInInbox: Bool
    @Property(title: "Is Archived")
    public var isArchived: Bool
    @Property(title: "Is in Spam")
    public var isInSpam: Bool
    @Property(title: "Is in Trash")
    public var isInTrash: Bool
    @Property(title: "Is Pinned")
    public var isPinned: Bool
    @Property(title: "Is Muted")
    public var isMuted: Bool
    @Property(title: "Is Snoozed")
    public var isSnoozed: Bool
    @Property(title: "Snoozed Until")
    public var snoozedUntil: Date?

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(senderName.isEmpty ? senderAddress : senderName)")
    }

    /// A conversation as filters see it, with the cached messages it holds.
    init(_ facts: MailFacts, messages: [MessageEntity]) {
        let envelope = facts.envelope
        id = EntityID.string(envelope.thread)
        title = envelope.subject
        description = envelope.snippet.isEmpty ? nil : envelope.snippet
        self.messages = messages
        senderName = envelope.sender.name ?? ""
        senderAddress = envelope.sender.address
        senderDomain = facts.texts(.senderDomain)?.first ?? ""
        date = envelope.date
        messageCount = envelope.messageCount
        labels = facts.texts(.mailbox) ?? []
        accountAddress = envelope.account.email
        isUnread = facts.flag(.unread) == true
        isStarred = facts.flag(.starred) == true
        isImportant = facts.flag(.important) == true
        isInInbox = facts.flag(.inInbox) == true
        isArchived = facts.flag(.archived) == true
        isInSpam = facts.flag(.inSpam) == true
        isInTrash = facts.flag(.inTrash) == true
        isPinned = facts.local.isPinned
        isMuted = facts.flag(.muted) == true
        isSnoozed = facts.flag(.snoozed) == true
        snoozedUntil = facts.date(.snoozedUntil)
    }

    /// A conversation an extension only points at, as a widget's button does: it names the thread, and the intent
    /// that gets it reads the rest from the store.
    public init(_ thread: ThreadSummary) {
        let account = Account(id: thread.id.accountID, email: "", color: .blue, service: .gmail)
        self.init(MailFacts(thread: thread, account: account), messages: [])
    }

    var threadID: ThreadSummary.ID? { EntityID.thread(id) }
}

extension ThreadEntity: IndexedEntity {
    public var attributeSet: CSSearchableItemAttributeSet {
        let attributes = defaultAttributeSet
        attributes.title = title
        attributes.contentDescription = description
        attributes.authorNames = [senderName.isEmpty ? senderAddress : senderName]
        attributes.contentCreationDate = date
        return attributes
    }
}
