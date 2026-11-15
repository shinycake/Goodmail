import Foundation
import MailCore

/// An action the reader can place on a side of a mailbox row.
nonisolated public enum SwipeChoice: String, CaseIterable, Sendable {
    case read, star, archive, snooze, trash, spam

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
    public enum Side: CaseIterable, Sendable {
        case leading, trailing
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

    /// Puts `choice` last on `side`, taking it off the other side. Does nothing when `side` is full.
    public mutating func add(_ choice: SwipeChoice, to side: Side) {
        guard hasRoom(on: side), !self[side].contains(choice) else { return }
        leading.removeAll { $0 == choice }
        trailing.removeAll { $0 == choice }
        update(side) { $0.append(choice) }
    }

    /// Takes the choices at `offsets` off `side`.
    public mutating func remove(at offsets: IndexSet, from side: Side) {
        update(side) { choices in
            choices = choices.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
        }
    }

    /// Moves the choices at `offsets` on `side` to before the one at `destination`, as a list's reordering does.
    public mutating func move(from offsets: IndexSet, to destination: Int, on side: Side) {
        update(side) { choices in
            let moving = offsets.map { choices[$0] }
            let target = destination - offsets.count { $0 < destination }
            choices = choices.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
            choices.insert(contentsOf: moving, at: min(max(0, target), choices.count))
        }
    }

    /// The buttons `side` shows for `thread` standing at `place`, edge-most first: each choice's swipe where it means
    /// something there, in the choice's tint.
    func buttons(for thread: ThreadSummary, at place: ThreadPlace, on side: Side, tints: SwipeTints)
        -> [MailboxViewModel.SwipeButton]
    {
        self[side].compactMap { choice in
            choice.swipe(for: thread, at: place).map { MailboxViewModel.SwipeButton(swipe: $0, tint: tints[choice]) }
        }
    }

    private mutating func update(_ side: Side, _ change: (inout [SwipeChoice]) -> Void) {
        switch side {
        case .leading: change(&leading)
        case .trailing: change(&trailing)
        }
    }
}
