import Foundation
import MailCore

/// `WindowState` as builds before `Reading` declared it, its coding left to Swift as they left it, so the tests can
/// check that states travel both ways between those builds and this one.
struct OldWindowState: Equatable, Codable {
    enum List: Equatable, Codable {
        case mailbox(Mailbox, thread: ThreadSummary.ID?)
        case scheduled
        case snoozed(thread: ThreadSummary.ID?)
        case smart(SmartMailbox.ID, thread: ThreadSummary.ID?)
    }

    var list: List
    var category: InboxCategory
    var filter = ListFilter.none
    var layout = WindowState.Layout.viewer

    private enum CodingKeys: String, CodingKey {
        case list, category, filter, layout
    }

    init(
        list: List, category: InboxCategory = .primary, filter: ListFilter = .none,
        layout: WindowState.Layout = .viewer
    ) {
        self.list = list
        self.category = category
        self.filter = filter
        self.layout = layout
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        list = try container.decode(List.self, forKey: .list)
        category = try container.decode(InboxCategory.self, forKey: .category)
        filter = try container.decodeIfPresent(ListFilter.self, forKey: .filter) ?? .none
        let layout = try container.decodeIfPresent(WindowState.Layout.self, forKey: .layout) ?? .viewer
        self.layout = openThread == nil ? .viewer : layout
    }

    var openThread: ThreadSummary.ID? {
        switch list {
        case .mailbox(_, let thread), .snoozed(let thread), .smart(_, let thread): thread
        case .scheduled: nil
        }
    }
}
