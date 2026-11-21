public import Foundation

/// A window's state as it is saved for restoration and travels in Handoff, in the shape builds before `Reading` wrote
/// and read, so either way across builds a window comes back: the conversation read rides in the list, as it did, and
/// the mailbox it reads in is one key of its own, `readingMailbox`, which older builds ignore. A state without that
/// key reads its conversation where its list reads, as older builds did.
///
/// A state saved before windows had a filter reads as unfiltered; one saved with a list title still reads, the key
/// ignored; one saved before layouts is a viewer.
extension WindowState: Codable {
    private enum CodingKeys: String, CodingKey {
        case list, category, filter, layout, readingMailbox
    }

    /// The list's one key, naming its case, as Swift writes an enum's cases.
    private enum ListKeys: String, CodingKey {
        case mailbox, scheduled, snoozed, smart
    }

    /// What a list's case holds: its mailbox or smart mailbox, unlabeled, and the conversation read over it.
    private enum CaseKeys: String, CodingKey {
        case value = "_0"
        case thread
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let lists = try container.nestedContainer(keyedBy: ListKeys.self, forKey: .list)
        guard lists.allKeys.count == 1, let key = lists.allKeys.first else {
            throw DecodingError.dataCorruptedError(
                forKey: .list, in: container, debugDescription: "A list names exactly one case")
        }
        let held = try lists.nestedContainer(keyedBy: CaseKeys.self, forKey: key)
        let list: List =
            switch key {
            case .mailbox: .mailbox(try held.decode(Mailbox.self, forKey: .value))
            case .scheduled: .scheduled
            case .snoozed: .snoozed
            case .smart: .smart(try held.decode(SmartMailbox.ID.self, forKey: .value))
            }
        self.init(
            list: list, category: try container.decode(InboxCategory.self, forKey: .category),
            filter: try container.decodeIfPresent(ListFilter.self, forKey: .filter) ?? .none)
        let mailbox = try container.decodeIfPresent(Mailbox.self, forKey: .readingMailbox) ?? list.readingMailbox
        if let thread = try held.decodeIfPresent(ThreadSummary.ID.self, forKey: .thread), let mailbox {
            read(Reading(thread, in: mailbox))
        }
        self = laidOut(as: try container.decodeIfPresent(Layout.self, forKey: .layout) ?? .viewer)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        var lists = container.nestedContainer(keyedBy: ListKeys.self, forKey: .list)
        var held: KeyedEncodingContainer<CaseKeys>
        switch list {
        case .mailbox(let mailbox):
            held = lists.nestedContainer(keyedBy: CaseKeys.self, forKey: .mailbox)
            try held.encode(mailbox, forKey: .value)
        case .scheduled:
            // Older builds read Scheduled as having nothing in it, so they restore it without the conversation.
            held = lists.nestedContainer(keyedBy: CaseKeys.self, forKey: .scheduled)
        case .snoozed:
            held = lists.nestedContainer(keyedBy: CaseKeys.self, forKey: .snoozed)
        case .smart(let id):
            held = lists.nestedContainer(keyedBy: CaseKeys.self, forKey: .smart)
            try held.encode(id, forKey: .value)
        }
        try held.encodeIfPresent(reading?.thread, forKey: .thread)
        try container.encodeIfPresent(reading?.mailbox, forKey: .readingMailbox)
        try container.encode(category, forKey: .category)
        try container.encode(filter, forKey: .filter)
        try container.encode(layout, forKey: .layout)
    }

    /// Reads a state `saved()` wrote. Throws for anything else, such as data from a later build.
    public init(saved data: Data) throws {
        self = try JSONDecoder().decode(Self.self, from: data)
    }

    public func saved() throws -> Data {
        try JSONEncoder().encode(self)
    }
}
