public import AppIntents
public import CoreSpotlight
public import MailCore

/// A conversation, as Siri, Shortcuts and Spotlight see it, with every fact its list row knows for Find and Filter.
@AppEntity(schema: .mail.thread)
public struct ThreadEntity: Sendable {
    public static let defaultQuery = ThreadQuery()

    public let id: String
    public var title: String
    public var description: String?
    /// The messages cached on the device, oldest first. A thread only listed so far has none yet.
    public var messages: [MessageEntity]

    /// Who wrote the latest message, to hand to Find's From or to another action.
    @Property(title: LocalizedStringResource("From", table: "ShortcutFlow"))
    public var from: SenderEntity
    @Property(title: LocalizedStringResource("Sender Name", table: "ShortcutMail"))
    public var senderName: String
    @Property(title: LocalizedStringResource("Sender Address", table: "ShortcutMail"))
    public var senderAddress: String
    @Property(title: LocalizedStringResource("Sender Domain", table: "ShortcutMail"))
    public var senderDomain: String
    /// The latest message's date, which Spotlight sorts by.
    @Property(title: LocalizedStringResource("Date", table: "ShortcutMail"))
    public var date: Date
    /// Whole days since its latest message, so Find can ask for conversations older than a week.
    @Property(title: LocalizedStringResource("Days Old", table: "ShortcutFlow"))
    public var daysOld: Int
    @Property(title: LocalizedStringResource("Number of Messages", table: "ShortcutMail"))
    public var messageCount: Int
    /// Every label and mailbox it's in, as Inbox, Starred or Receipts.
    @Property(title: LocalizedStringResource("Labels", table: "ShortcutMail"))
    public var labels: [String]
    @Property(title: LocalizedStringResource("Account Address", table: "ShortcutMail"))
    public var accountAddress: String
    @Property(title: LocalizedStringResource("Is Unread", table: "ShortcutMail"))
    public var isUnread: Bool
    @Property(title: LocalizedStringResource("Is Starred", table: "ShortcutMail"))
    public var isStarred: Bool
    @Property(title: LocalizedStringResource("Is Important", table: "ShortcutMail"))
    public var isImportant: Bool
    @Property(title: LocalizedStringResource("Is in Inbox", table: "ShortcutMail"))
    public var isInInbox: Bool
    @Property(title: LocalizedStringResource("Is Archived", table: "ShortcutMail"))
    public var isArchived: Bool
    @Property(title: LocalizedStringResource("Is in Spam", table: "ShortcutMail"))
    public var isInSpam: Bool
    @Property(title: LocalizedStringResource("Is in Trash", table: "ShortcutMail"))
    public var isInTrash: Bool
    @Property(title: LocalizedStringResource("Is Pinned", table: "ShortcutMail"))
    public var isPinned: Bool
    @Property(title: LocalizedStringResource("Is Muted", table: "ShortcutMail"))
    public var isMuted: Bool
    @Property(title: LocalizedStringResource("Is Snoozed", table: "ShortcutMail"))
    public var isSnoozed: Bool
    @Property(title: LocalizedStringResource("Snoozed Until", table: "ShortcutMail"))
    public var snoozedUntil: Date?

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(senderName.isEmpty ? senderAddress : senderName)")
    }

    /// A conversation as filters see it, with the cached messages it holds. `now` reads its age.
    init(_ facts: MailFacts, messages: [MessageEntity], now: Date = .now) {
        let envelope = facts.envelope
        id = EntityID.string(envelope.thread)
        title = envelope.subject
        description = envelope.snippet.isEmpty ? nil : envelope.snippet
        self.messages = messages
        from = SenderEntity(envelope.sender)
        senderName = envelope.sender.name ?? ""
        senderAddress = envelope.sender.address
        senderDomain = facts.texts(.senderDomain)?.first ?? ""
        date = envelope.date
        daysOld = DaysOld.of(envelope.date, now: now)
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
        attributes.authorEmailAddresses = [senderAddress]
        attributes.contentCreationDate = date
        // Spotlight finds a conversation by its labels and the sender's domain too, as "receipts" or "amazon".
        attributes.keywords = labels + [senderDomain].filter { !$0.isEmpty }
        return attributes
    }
}
