import Foundation
import MailCore

/// An action the reader can place on a side of a mailbox row.
nonisolated public enum SwipeChoice: String, CaseIterable, Identifiable, Sendable {
    case read, star, archive, snooze, trash, spam

    public var id: Self { self }

    /// What this choice does to `thread` standing at `place`, or `nil` where it means nothing there. Archive takes
    /// the thread out of the way where it is: out of the Inbox, out of Spam back to the Inbox, or out of Trash. Trash
    /// deletes a thread in the Trash list for good. Snooze needs the thread in the Inbox.
    func swipe(for thread: ThreadSummary, at place: ThreadPlace) -> MailboxViewModel.Swipe? {
        switch self {
        case .read: return .perform(.markRead(thread.isUnread))
        case .star: return .perform(.star(!thread.labelIDs.contains(SystemLabel.starred)))
        case .archive:
            switch place {
            case .trash: return .perform(.untrash)
            case .spam: return .perform(.moveToInbox)
            case .inbox: return .perform(.archive)
            case .elsewhere: return nil
            }
        case .snooze: return place == .inbox ? .snooze : nil
        case .trash: return .perform(place == .trash ? .deleteForever : .trash)
        case .spam: return place.canReportSpam ? .perform(.reportSpam) : nil
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
    /// Where a choice can sit: on a side of the row, or set aside with the unused ones.
    public enum Shelf: Hashable, Sendable {
        case side(SwipeSide)
        case unused
    }

    public static let capacity = 3
    /// Reading state and star on the left; Archive, Snooze and Trash on the right.
    public static let standard = SwipeArrangement(left: [.read, .star], right: [.archive, .snooze, .trash])

    public private(set) var left: [SwipeChoice]
    public private(set) var right: [SwipeChoice]

    /// Drops repeats, keeping a choice's first place (the left side's over the right one's), and anything past
    /// a side's capacity.
    public init(left: [SwipeChoice], right: [SwipeChoice]) {
        var placed = Set<SwipeChoice>()
        func keep(_ choices: [SwipeChoice]) -> [SwipeChoice] {
            Array(choices.filter { placed.insert($0).inserted }.prefix(Self.capacity))
        }
        self.left = keep(left)
        self.right = keep(right)
    }

    public subscript(side: SwipeSide) -> [SwipeChoice] {
        switch side {
        case .left: left
        case .right: right
        }
    }

    /// The choices on neither side, in their usual order.
    public var unused: [SwipeChoice] {
        SwipeChoice.allCases.filter { !left.contains($0) && !right.contains($0) }
    }

    public func hasRoom(on side: SwipeSide) -> Bool {
        self[side].count < Self.capacity
    }

    /// Puts `choices` on `shelf` in their order, before `anchor` or last, taking them off wherever they sat: one
    /// move covers adding, reordering, crossing sides and setting aside. Changes nothing when it would overfill a side,
    /// or when the choices are dropped before one of themselves.
    public mutating func move(_ choices: [SwipeChoice], to shelf: Shelf, before anchor: SwipeChoice? = nil) {
        if let anchor, choices.contains(anchor) { return }
        var moved = self
        moved.left.removeAll(where: choices.contains)
        moved.right.removeAll(where: choices.contains)
        if case .side(let side) = shelf {
            var placed = moved[side]
            placed.insert(contentsOf: choices, at: anchor.flatMap(placed.firstIndex) ?? placed.endIndex)
            guard placed.count <= Self.capacity else { return }
            moved.update(side) { $0 = placed }
        }
        self = moved
    }

    /// The buttons `side` shows for `thread` standing at `place`, edge-most first: each choice's swipe where it means
    /// something there, in the choice's tint.
    func buttons(for thread: ThreadSummary, at place: ThreadPlace, on side: SwipeSide, tints: SwipeTints)
        -> [MailboxViewModel.SwipeButton]
    {
        self[side].compactMap { choice in
            choice.swipe(for: thread, at: place).map {
                MailboxViewModel.SwipeButton(choice: choice, swipe: $0, tint: tints[choice])
            }
        }
    }

    private mutating func update(_ side: SwipeSide, _ change: (inout [SwipeChoice]) -> Void) {
        switch side {
        case .left: change(&left)
        case .right: change(&right)
        }
    }
}
