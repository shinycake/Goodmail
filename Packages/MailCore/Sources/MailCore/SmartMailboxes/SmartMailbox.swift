public import Foundation

/// A saved search in the sidebar, as Apple Mail's smart mailboxes: a name, a symbol, and what its mail must be. Its
/// list and unread count come from the mail on the device, so they work offline within the offline window (ADR-007).
/// The reader's smart mailboxes follow them to their other devices (ADR-039), merged by `id`.
public struct SmartMailbox: Identifiable, Codable, Hashable, Sendable {
    /// The same on every device, so an edit made on one replaces the box on the others rather than adding a copy.
    public struct ID: RawRepresentable, Hashable, Codable, Sendable {
        public let rawValue: String

        public init(rawValue: String) {
            self.rawValue = rawValue
        }
    }

    /// What the sidebar calls the box. The starting set's names are read in each device's language until the reader
    /// renames them.
    public enum Name: Codable, Hashable, Sendable {
        case unread
        case vips
        case withAttachments
        case custom(String)
    }

    /// What mail the box holds.
    public enum Filter: Codable, Hashable, Sendable {
        /// Mail from the reader's VIPs, whoever they are at the time.
        case vips
        case condition(MailCondition)
    }

    public var id: ID
    public var name: Name
    /// An SF Symbol's name.
    public var symbol: String
    public var filter: Filter

    public init(id: ID = ID(rawValue: UUID().uuidString), name: Name, symbol: String, filter: Filter) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.filter = filter
    }

    /// What a mail must meet to be in the box, with `vips` the reader's VIPs now (ADR-038). With no VIPs, the VIPs box
    /// holds nothing.
    public func condition(vips: VIPList) -> MailCondition {
        switch filter {
        case .vips: vips.condition
        case .condition(let condition): condition
        }
    }

    /// The boxes a new database starts with, each deletable. Their IDs are fixed, so the copies every device starts
    /// with are one box to the settings sync, and a box deleted on one device goes on all of them.
    public static let startingSet = [
        SmartMailbox(
            id: ID(rawValue: "unread"), name: .unread, symbol: "envelope.badge",
            filter: .condition(.flag(.unread, true))),
        SmartMailbox(id: ID(rawValue: "vips"), name: .vips, symbol: "crown", filter: .vips),
        SmartMailbox(
            id: ID(rawValue: "attachments"), name: .withAttachments, symbol: "paperclip",
            filter: .condition(.flag(.hasAttachments, true))),
    ]
}

/// The reader's smart mailboxes in their order, with each one's unread conversations, for the sidebar.
public struct SmartMailboxDirectory: Equatable, Sendable {
    public var mailboxes: [SmartMailbox]
    /// Unread conversations per box; boxes with none are left out.
    public var unreadCounts: [SmartMailbox.ID: Int]

    public init(mailboxes: [SmartMailbox] = [], unreadCounts: [SmartMailbox.ID: Int] = [:]) {
        self.mailboxes = mailboxes
        self.unreadCounts = unreadCounts
    }
}
