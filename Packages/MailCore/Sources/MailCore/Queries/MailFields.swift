public import Foundation

// What a filter, a sort or a rule can ask about a mail (`MailCondition`, `MailSort`). Each field is answered by
// `MailFacts`.

/// A field read as text. A field holding several values, as recipients, matches when any one of them does.
public enum TextField: String, CaseIterable, Codable, Hashable, Sendable {
    case subject
    /// The body as plain text.
    case body
    /// The provider's preview of the body.
    case snippet
    /// The sender's name and address, so "from Dana" and "from dana@x.com" both match.
    case sender
    case senderName
    case senderAddress
    /// The part of the sender's address after `@`, as `amazon.com`.
    case senderDomain
    /// Each To recipient's name and address.
    case to
    case cc
    case bcc
    case replyTo
    /// Every To, Cc and Bcc recipient's name and address.
    case recipients
    case attachmentName
    /// Each attachment's MIME type, as `application/pdf`.
    case attachmentType
    /// The names of the labels or folders the mail is in, the standard mailboxes included, as Inbox and Starred.
    case mailbox
    /// The address of the account the mail is in.
    case account
    /// The link or address the mailing list's List-Unsubscribe header gives.
    case unsubscribe
    /// The RFC 5322 Message-ID.
    case internetMessageID
    /// The subject, the sender, the preview and the body: what a word typed in search reads. A conversation only
    /// listed so far answers with what its row shows.
    case anyText
}

/// A field read as a number.
public enum NumberField: String, CaseIterable, Codable, Hashable, Sendable {
    case toCount
    case ccCount
    case bccCount
    /// To, Cc and Bcc together.
    case recipientCount
    case attachmentCount
    /// Every attachment's size together, in bytes.
    case attachmentSize
    /// How many messages the conversation holds.
    case messageCount
    /// How many characters the plain-text body holds.
    case bodyLength
    /// The largest sum of money the body names (`MoneyAmount`).
    case largestAmount
    /// The sum of money the body's total line names (`MoneyAmount.total(in:)`).
    case totalAmount
}

/// A field read as a date.
public enum DateField: String, CaseIterable, Codable, Hashable, Sendable {
    /// When the mail was sent, which is when it was received to within the delivery's delay.
    case date
    /// When a snoozed conversation comes back to the Inbox.
    case snoozedUntil
}

/// A yes-or-no fact about a mail.
public enum MailFlag: String, CaseIterable, Codable, Hashable, Sendable {
    case unread
    case starred
    /// Gmail's Important marker.
    case important
    case hasAttachments
    case inInbox
    /// Out of the Inbox, and in neither Spam nor Trash.
    case archived
    case inSpam
    case inTrash
    case draft
    /// Sent from the account's own address or one of its aliases.
    case fromMe
    /// The account's address is among the To recipients, not only Cc or Bcc.
    case toMe
    /// A reply: it names the message it answers, or its subject starts with "Re:".
    case reply
    /// Its subject starts with "Fwd:" or "Fw:".
    case forward
    case pinned
    case snoozed
    case muted
    /// It came from a mailing list that says how to leave it.
    case hasUnsubscribe
}

/// How a text field compares. Every comparison ignores case and diacritics, as Shortcuts' own do.
public enum TextMatch: Codable, Hashable, Sendable {
    case contains(String)
    case equals(String)
    case beginsWith(String)
    case endsWith(String)
    /// A regular expression, for anything the others can't say. One that doesn't compile matches nothing.
    case matchesPattern(String)
    /// The field has no value, or only an empty one.
    case isEmpty
}

/// How a number field compares.
public enum NumberMatch: Codable, Hashable, Sendable {
    case equals(Double)
    case lessThan(Double)
    case greaterThan(Double)
    case atMost(Double)
    case atLeast(Double)
    /// From the lower bound to the upper, both included.
    case between(Double, Double)
}

/// How a date field compares.
public enum DateMatch: Codable, Hashable, Sendable {
    case before(Date)
    case after(Date)
    /// From the first date to the second, both included.
    case between(Date, Date)
    /// Up to `seconds` before now, which a rule saved today keeps meaning tomorrow.
    case withinLast(seconds: Double)
}

/// A day of the week, numbered as `Calendar` numbers them.
public enum Weekday: Int, CaseIterable, Codable, Hashable, Sendable {
    case sunday = 1
    case monday, tuesday, wednesday, thursday, friday, saturday
}

/// A time on the clock, in the calendar's time zone.
public struct TimeOfDay: Hashable, Codable, Comparable, Sendable {
    public var hour: Int
    public var minute: Int

    public init(hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
    }

    var minutes: Int { hour * 60 + minute }

    public static func < (lhs: TimeOfDay, rhs: TimeOfDay) -> Bool { lhs.minutes < rhs.minutes }
}
