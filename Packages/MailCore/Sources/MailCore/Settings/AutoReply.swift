import Foundation

/// The reply a service sends for the reader while they are away: when it runs, what it says, and to whom.
public struct AutoReply: Equatable, Sendable {
    /// When the service replies.
    public enum Schedule: Equatable, Sendable {
        case off
        /// From now until the reader turns it off.
        case on
        /// Only between these times.
        case between(DateInterval)
    }

    public var schedule: Schedule
    /// The reply's subject. Not every service has one: Outlook replies keep the original's.
    public var subject: String
    /// The reply, as plain text.
    public var message: String
    /// Whether only the reader's contacts get it, so strangers and lists don't learn they are away.
    public var contactsOnly: Bool

    public init(schedule: Schedule = .off, subject: String = "", message: String = "", contactsOnly: Bool = false) {
        self.schedule = schedule
        self.subject = subject
        self.message = message
        self.contactsOnly = contactsOnly
    }
}

/// A provider whose service sends automatic replies: Gmail's vacation responder and Outlook's automatic replies.
/// iCloud has no API for its own, so it doesn't conform.
public protocol AutoReplying: Sendable {
    /// Whether the service's replies have a subject of their own.
    var autoReplyHasSubject: Bool { get }
    func autoReply() async throws -> AutoReply
    func setAutoReply(_ reply: AutoReply) async throws
}
