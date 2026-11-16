public import AppIntents
public import Foundation
import MailCore

/// One message of a thread, as Siri, Shortcuts and Apple Intelligence see it. Only cached messages are entities: the
/// rest have no body or recipients on the device yet.
///
/// The mail schema's properties come first. Goodmail adds every other fact a filter or a rule can ask
/// (`MailFacts`), so Shortcuts' Find and Filter actions, and the Use Model action, can work on any of them.
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

    // MARK: People

    @Property(title: "Sender Name")
    public var senderName: String
    @Property(title: "Sender Address")
    public var senderAddress: String
    /// The part of the sender's address after `@`, as `amazon.com`.
    @Property(title: "Sender Domain")
    public var senderDomain: String
    @Property(title: "Reply-To Addresses")
    public var replyToAddresses: [String]
    /// Every To, Cc and Bcc address.
    @Property(title: "Recipient Addresses")
    public var recipientAddresses: [String]
    @Property(title: "Number of To Recipients")
    public var toCount: Int
    @Property(title: "Number of Cc Recipients")
    public var ccCount: Int
    @Property(title: "Number of Bcc Recipients")
    public var bccCount: Int
    @Property(title: "Number of Recipients")
    public var recipientCount: Int
    @Property(title: "Is From Me")
    public var isFromMe: Bool
    /// The account's address is a To recipient, not only Cc or Bcc.
    @Property(title: "Is Addressed to Me")
    public var isToMe: Bool

    // MARK: Text

    @Property(title: "Preview")
    public var snippet: String
    /// What a total line in the body names, as "Order total: $54.20" (`MoneyAmount.total(in:)`).
    @Property(title: "Total Price")
    public var totalAmount: Double?
    @Property(title: "Highest Price")
    public var largestAmount: Double?
    /// Every sum of money the body names, in order.
    @Property(title: "Prices")
    public var amounts: [Double]
    /// ISO 4217, as USD, of the total or else the first price.
    @Property(title: "Currency")
    public var currency: String?
    @Property(title: "Message-ID")
    public var internetMessageID: String?

    // MARK: Where and when

    /// Every label and mailbox it's in, as Inbox, Starred or Receipts.
    @Property(title: "Labels")
    public var labels: [String]
    @Property(title: "Day of the Week")
    public var weekday: WeekdayEntity
    /// The hour it arrived, from 0 to 23.
    @Property(title: "Hour Received")
    public var hour: Int
    @Property(title: "Messages in Conversation")
    public var conversationLength: Int

    // MARK: State

    @Property(title: "Is Important")
    public var isImportant: Bool
    @Property(title: "Is in Inbox")
    public var isInInbox: Bool
    @Property(title: "Is Archived")
    public var isArchived: Bool
    @Property(title: "Is in Trash")
    public var isInTrash: Bool
    @Property(title: "Is Draft")
    public var isDraft: Bool
    @Property(title: "Is Reply")
    public var isReply: Bool
    @Property(title: "Is Forward")
    public var isForward: Bool
    @Property(title: "Is Pinned")
    public var isPinned: Bool
    @Property(title: "Is Muted")
    public var isMuted: Bool
    @Property(title: "Is Snoozed")
    public var isSnoozed: Bool
    @Property(title: "Snoozed Until")
    public var snoozedUntil: Date?

    // MARK: Attachments and lists

    @Property(title: "Has Attachments")
    public var hasAttachments: Bool
    @Property(title: "Number of Attachments")
    public var attachmentCount: Int
    @Property(title: "Attachment Names")
    public var attachmentNames: [String]
    @Property(title: "Attachments Size")
    public var attachmentSize: Measurement<UnitInformationStorage>
    @Property(title: "Is From a Mailing List")
    public var hasUnsubscribe: Bool
    /// Where the list's List-Unsubscribe header sends a reader who leaves it.
    @Property(title: "Unsubscribe Link")
    public var unsubscribeLink: String?

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(subject ?? "")", subtitle: "\(senderName.isEmpty ? senderAddress : senderName)")
    }

    /// The cached message `facts` describes, in `mailbox`. `calendar` reads its weekday and hour.
    init(_ facts: MailFacts, content: MailFacts.Content, mailbox: MailboxEntity, calendar: Calendar) {
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
