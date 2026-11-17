public import AppIntents
public import Foundation
import MailCore

/// One message of a thread, as Siri, Shortcuts and Apple Intelligence see it. Only cached messages are entities: the
/// rest have no body or recipients on the device yet.
///
/// The mail schema's properties come first. Goodmail adds every other fact a filter or a rule can ask
/// (`MailFacts`), so Shortcuts' Find and Filter actions, and the Use Model action, can work on any of them.
@AppEntity(schema: .mail.message)
public struct MessageEntity: Sendable {
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

    // MARK: People

    /// Who sent it, to hand to Find's From or to another action.
    @Property(title: LocalizedStringResource("From", table: "ShortcutFlow"))
    public var from: SenderEntity
    @Property(title: LocalizedStringResource("Sender Name", table: "ShortcutMail"))
    public var senderName: String
    @Property(title: LocalizedStringResource("Sender Address", table: "ShortcutMail"))
    public var senderAddress: String
    /// The part of the sender's address after `@`, as `amazon.com`.
    @Property(title: LocalizedStringResource("Sender Domain", table: "ShortcutMail"))
    public var senderDomain: String
    @Property(title: LocalizedStringResource("Reply-To Addresses", table: "ShortcutMail"))
    public var replyToAddresses: [String]
    /// Every To, Cc and Bcc address.
    @Property(title: LocalizedStringResource("Recipient Addresses", table: "ShortcutMail"))
    public var recipientAddresses: [String]
    @Property(title: LocalizedStringResource("Number of To Recipients", table: "ShortcutMail"))
    public var toCount: Int
    @Property(title: LocalizedStringResource("Number of Cc Recipients", table: "ShortcutMail"))
    public var ccCount: Int
    @Property(title: LocalizedStringResource("Number of Bcc Recipients", table: "ShortcutMail"))
    public var bccCount: Int
    @Property(title: LocalizedStringResource("Number of Recipients", table: "ShortcutMail"))
    public var recipientCount: Int
    @Property(title: LocalizedStringResource("Is From Me", table: "ShortcutMail"))
    public var isFromMe: Bool
    /// The account's address is a To recipient, not only Cc or Bcc.
    @Property(title: LocalizedStringResource("Is Addressed to Me", table: "ShortcutMail"))
    public var isToMe: Bool

    // MARK: Text

    @Property(title: LocalizedStringResource("Preview", table: "ShortcutMail"))
    public var snippet: String
    /// What a total line in the body names, as "Order total: $54.20" (`MoneyAmount.total(in:)`).
    @Property(title: LocalizedStringResource("Total Price", table: "ShortcutMail"))
    public var totalAmount: Double?
    @Property(title: LocalizedStringResource("Highest Price", table: "ShortcutMail"))
    public var largestAmount: Double?
    /// Every sum of money the body names, in order.
    @Property(title: LocalizedStringResource("Prices", table: "ShortcutMail"))
    public var amounts: [Double]
    /// ISO 4217, as USD, of the total or else the first price.
    @Property(title: LocalizedStringResource("Currency", table: "ShortcutMail"))
    public var currency: String?
    @Property(title: LocalizedStringResource("Message-ID", table: "ShortcutMail"))
    public var internetMessageID: String?

    // MARK: Where and when

    /// Every label and mailbox it's in, as Inbox, Starred or Receipts.
    @Property(title: LocalizedStringResource("Labels", table: "ShortcutMail"))
    public var labels: [String]
    @Property(title: LocalizedStringResource("Day of the Week", table: "ShortcutMail"))
    public var weekday: WeekdayEntity
    /// The hour it arrived, from 0 to 23.
    @Property(title: LocalizedStringResource("Hour Received", table: "ShortcutMail"))
    public var hour: Int
    @Property(title: LocalizedStringResource("Messages in Conversation", table: "ShortcutMail"))
    public var conversationLength: Int
    /// Whole days since it arrived, so Find can ask for mail older than a week.
    @Property(title: LocalizedStringResource("Days Old", table: "ShortcutFlow"))
    public var daysOld: Int
    /// The conversation it belongs to, for the actions that archive, move, snooze or label conversations. Its own
    /// messages aren't in it; Get Messages in Conversations gets them.
    @Property(title: LocalizedStringResource("Conversation", table: "ShortcutFlow"))
    public var conversation: ThreadEntity

    // MARK: State

    @Property(title: LocalizedStringResource("Is Important", table: "ShortcutMail"))
    public var isImportant: Bool
    @Property(title: LocalizedStringResource("Is in Inbox", table: "ShortcutMail"))
    public var isInInbox: Bool
    @Property(title: LocalizedStringResource("Is Archived", table: "ShortcutMail"))
    public var isArchived: Bool
    @Property(title: LocalizedStringResource("Is in Trash", table: "ShortcutMail"))
    public var isInTrash: Bool
    @Property(title: LocalizedStringResource("Is Draft", table: "ShortcutMail"))
    public var isDraft: Bool
    @Property(title: LocalizedStringResource("Is Reply", table: "ShortcutMail"))
    public var isReply: Bool
    @Property(title: LocalizedStringResource("Is Forward", table: "ShortcutMail"))
    public var isForward: Bool
    @Property(title: LocalizedStringResource("Is Pinned", table: "ShortcutMail"))
    public var isPinned: Bool
    @Property(title: LocalizedStringResource("Is Muted", table: "ShortcutMail"))
    public var isMuted: Bool
    @Property(title: LocalizedStringResource("Is Snoozed", table: "ShortcutMail"))
    public var isSnoozed: Bool
    @Property(title: LocalizedStringResource("Snoozed Until", table: "ShortcutMail"))
    public var snoozedUntil: Date?

    // MARK: Attachments and lists

    @Property(title: LocalizedStringResource("Has Attachments", table: "ShortcutMail"))
    public var hasAttachments: Bool
    @Property(title: LocalizedStringResource("Number of Attachments", table: "ShortcutMail"))
    public var attachmentCount: Int
    @Property(title: LocalizedStringResource("Attachment Names", table: "ShortcutMail"))
    public var attachmentNames: [String]
    @Property(title: LocalizedStringResource("Attachments Size", table: "ShortcutMail"))
    public var attachmentSize: Measurement<UnitInformationStorage>
    @Property(title: LocalizedStringResource("Is From a Mailing List", table: "ShortcutMail"))
    public var hasUnsubscribe: Bool
    /// Where the list's List-Unsubscribe header sends a reader who leaves it.
    @Property(title: LocalizedStringResource("Unsubscribe Link", table: "ShortcutMail"))
    public var unsubscribeLink: String?

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(subject ?? "")", subtitle: "\(senderName.isEmpty ? senderAddress : senderName)")
    }

    /// The cached message `facts` describes, in `mailbox`, of `conversation`. `calendar` reads its weekday and hour,
    /// and `now` its age.
    init(
        _ facts: MailFacts, content: MailFacts.Content, mailbox: MailboxEntity, conversation: ThreadEntity,
        calendar: Calendar, now: Date
    ) {
        let envelope = facts.envelope
        id = EntityID.string(content.id, inThread: envelope.thread.threadID)
        subject = envelope.subject.isEmpty ? nil : envelope.subject
        body = content.bodyText.isEmpty ? nil : content.bodyText
        sender = IntentPerson(envelope.sender)
        to = content.to.map(IntentPerson.init)
        cc = content.cc.map(IntentPerson.init)
        bcc = content.bcc.map(IntentPerson.init)
        dateSent = envelope.date
        dateReceived = envelope.date
        isRead = facts.flag(.unread) == false
        isFlagged = facts.flag(.starred) == true
        isJunk = facts.flag(.inSpam) == true
        // Attachments are fetched when asked for (Get Attachments); the entity names them without their data.
        attachments = []
        self.mailbox = mailbox
        account = mailbox.account
        category = facts.category.flatMap { MailCategoryEntity(rawValue: $0.rawValue) }

        from = SenderEntity(envelope.sender)
        senderName = envelope.sender.name ?? ""
        senderAddress = envelope.sender.address
        senderDomain = facts.texts(.senderDomain)?.first ?? ""
        replyToAddresses = content.replyTo.map(\.address)
        recipientAddresses = (content.to + content.cc + content.bcc).map(\.address)
        toCount = content.to.count
        ccCount = content.cc.count
        bccCount = content.bcc.count
        recipientCount = recipientAddresses.count
        isFromMe = facts.flag(.fromMe) == true
        isToMe = facts.flag(.toMe) == true

        snippet = envelope.snippet
        let prices = MoneyAmount.all(in: content.bodyText)
        let total = MoneyAmount.total(in: content.bodyText)
        amounts = prices.map(\.value.doubleValue)
        totalAmount = total?.value.doubleValue
        largestAmount = amounts.max()
        currency = (total ?? prices.first)?.currency
        internetMessageID = content.internetMessageID

        labels = facts.texts(.mailbox) ?? []
        weekday = WeekdayEntity(calendar.component(.weekday, from: envelope.date))
        hour = calendar.component(.hour, from: envelope.date)
        conversationLength = envelope.messageCount
        daysOld = DaysOld.of(envelope.date, now: now)
        self.conversation = conversation

        isImportant = facts.flag(.important) == true
        isInInbox = facts.flag(.inInbox) == true
        isArchived = facts.flag(.archived) == true
        isInTrash = facts.flag(.inTrash) == true
        isDraft = facts.flag(.draft) == true
        isReply = facts.flag(.reply) == true
        isForward = facts.flag(.forward) == true
        isPinned = facts.local.isPinned
        isMuted = facts.flag(.muted) == true
        isSnoozed = facts.flag(.snoozed) == true
        snoozedUntil = facts.date(.snoozedUntil)

        hasAttachments = !content.attachments.isEmpty
        attachmentCount = content.attachments.count
        attachmentNames = content.attachments.map(\.filename)
        attachmentSize = Measurement(
            value: Double(content.attachments.reduce(0) { $0 + $1.size }), unit: .bytes)
        hasUnsubscribe = content.unsubscribe != nil
        unsubscribeLink = facts.texts(.unsubscribe)?.first
    }

    var threadID: ThreadSummary.ID? { EntityID.message(id)?.thread }
}

extension IntentPerson {
    init(_ contact: Contact) {
        self.init(
            identifier: .applicationDefined(contact.address),
            name: contact.name.map { .displayName($0) } ?? .unknown,
            handle: IntentPerson.Handle(emailAddress: contact.address))
    }
}

extension Decimal {
    /// The value as written, so 49.99 stays 49.99 rather than the nearest binary fraction NSDecimalNumber gives.
    var doubleValue: Double { Double(description) ?? NSDecimalNumber(decimal: self).doubleValue }
}
