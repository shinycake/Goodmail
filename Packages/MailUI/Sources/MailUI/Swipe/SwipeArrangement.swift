import Foundation
import MailCore

/// An action the reader can place on a side of a mailbox row.
nonisolated public enum SwipeChoice: String, CaseIterable, Identifiable, Sendable {
    case read, star, archive, snooze, trash, spam

    public var id: Self { self }

    /// What this choice does to `thread`, or `nil` where it means nothing there. Archive takes the thread out of the
    /// way where it is: out of the Inbox, out of Spam back to the Inbox, or out of Trash. Trash deletes a thread
    /// already in Trash for good. Snooze needs the thread in the Inbox.
    func swipe(for thread: ThreadSummary) -> MailboxViewModel.Swipe? {
        let labels = thread.labelIDs
        switch self {
        case .read: return .perform(.markRead(thread.isUnread))
        case .star: return .perform(.star(!labels.contains(SystemLabel.starred)))
        case .archive:
            if labels.contains(SystemLabel.trash) { return .perform(.untrash) }
            if labels.contains(SystemLabel.spam) { return .perform(.moveToInbox) }
            return labels.contains(SystemLabel.inbox) ? .perform(.archive) : nil
        case .snooze: return MailboxViewModel.canSnooze([thread]) ? .snooze : nil
        case .trash: return .perform(labels.contains(SystemLabel.trash) ? .deleteForever : .trash)
        case .spam:
            return labels.isDisjoint(with: [SystemLabel.spam, SystemLabel.trash]) ? .perform(.reportSpam) : nil
        }
    }
}

extension SwipeChoice {
    /// The choice's name in Settings.
    var title: String {
        switch self {
        case .read:
            String(
                localized: "Read or Unread", table: "Swipe", bundle: .module,
                comment: "Swipe action choice: mark a thread read, or unread if it is read")
        case .star:
            String(
                localized: "Star or Unstar", table: "Swipe", bundle: .module,
                comment: "Swipe action choice: star a thread, or unstar it if it is starred")
        case .archive:
            String(
                localized: "Archive", table: "Swipe", bundle: .module,
                comment: "Swipe action choice: take a thread out of the Inbox, Spam or Trash")
        case .snooze: String(localized: "Snooze", table: "Swipe", bundle: .module, comment: "Swipe action choice")
        case .trash: String(localized: "Trash", table: "Swipe", bundle: .module, comment: "Swipe action choice")
        case .spam: String(localized: "Report Spam", table: "Swipe", bundle: .module, comment: "Swipe action choice")
        }
    }

    var symbol: String {
        switch self {
        case .read: ThreadAction.markRead(true).symbol
        case .star: ThreadAction.star(true).symbol
        case .archive: ThreadAction.archive.symbol
        case .snooze: "clock"
        case .trash: ThreadAction.trash.symbol
        case .spam: ThreadAction.reportSpam.symbol
        }
    }
}

/// Which actions sit on each side of a mailbox row, edge-most first. A full swipe fires the first. Each choice sits
/// on one side at most, and a side holds at most `capacity`, so a full swipe still has room past the buttons.
nonisolated public struct SwipeArrangement: Equatable, Sendable {
    public enum Side: CaseIterable, Hashable, Sendable {
        case leading, trailing
    }

    /// Where a choice can sit: on a side of the row, or set aside with the unused ones.
    public enum Shelf: Hashable, Sendable {
        case side(Side)
        case unused
    }

    public static let capacity = 3
    /// Reading state and star from the leading edge; Archive, Snooze and Trash from the trailing one.
    public static let standard = SwipeArrangement(leading: [.read, .star], trailing: [.archive, .snooze, .trash])

    public private(set) var leading: [SwipeChoice]
    public private(set) var trailing: [SwipeChoice]

    /// Drops repeats, keeping a choice's first place (the leading side's over the trailing one's), and anything past
    /// a side's capacity.
    public init(leading: [SwipeChoice], trailing: [SwipeChoice]) {
        var placed = Set<SwipeChoice>()
        func keep(_ choices: [SwipeChoice]) -> [SwipeChoice] {
            Array(choices.filter { placed.insert($0).inserted }.prefix(Self.capacity))
        }
        self.leading = keep(leading)
        self.trailing = keep(trailing)
    }

    public subscript(side: Side) -> [SwipeChoice] {
        switch side {
        case .leading: leading
        case .trailing: trailing
        }
    }

    /// The choices on neither side, in their usual order.
    public var unused: [SwipeChoice] {
        SwipeChoice.allCases.filter { !leading.contains($0) && !trailing.contains($0) }
    }

    public func hasRoom(on side: Side) -> Bool {
        self[side].count < Self.capacity
    }

    /// Puts `choices` on `shelf` in their order, before `anchor` or last, taking them off wherever they sat: one
    /// move covers adding, reordering, crossing sides and setting aside. Changes nothing when it would overfill a side,
    /// or when the choices are dropped before one of themselves.
    public mutating func move(_ choices: [SwipeChoice], to shelf: Shelf, before anchor: SwipeChoice? = nil) {
        if let anchor, choices.contains(anchor) { return }
        var moved = self
        moved.leading.removeAll(where: choices.contains)
        moved.trailing.removeAll(where: choices.contains)
        if case .side(let side) = shelf {
            var placed = moved[side]
            placed.insert(contentsOf: choices, at: anchor.flatMap(placed.firstIndex) ?? placed.endIndex)
            guard placed.count <= Self.capacity else { return }
            moved.update(side) { $0 = placed }
        }
        self = moved
    }

    /// The swipes `side` shows for `thread`, edge-most first: each choice's swipe where it means something there.
    func swipes(for thread: ThreadSummary, on side: Side) -> [MailboxViewModel.Swipe] {
        self[side].compactMap { $0.swipe(for: thread) }
    }

    private mutating func update(_ side: Side, _ change: (inout [SwipeChoice]) -> Void) {
        switch side {
        case .leading: change(&leading)
        case .trailing: change(&trailing)
        }
    }
}
