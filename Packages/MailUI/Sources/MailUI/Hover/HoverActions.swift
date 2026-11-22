import Foundation
import MailCore

/// Whether a desktop window's rows show quick actions under the pointer, and which. They come from the same actions as
/// the swipes, at most `capacity`, in the order the reader put them.
nonisolated public enum HoverActions: Equatable, Sendable {
    case off
    case on(Picks)

    public static let capacity = 3
    public static let standard = HoverActions.on(.standard)

    /// The actions a row shows, in order; none while off.
    public var shown: [SwipeChoice] {
        switch self {
        case .off: []
        case .on(let picks): picks.choices
        }
    }

    /// Up to `capacity` actions, each once, in order.
    public struct Picks: Equatable, Sendable {
        public let choices: [SwipeChoice]

        /// Archive, Trash, then Read or Unread.
        public static let standard = Picks([.archive, .trash, .read])

        /// Keeps each action's first place, and the first `capacity` of them.
        public init(_ choices: [SwipeChoice]) {
            var seen = Set<SwipeChoice>()
            self.choices = Array(choices.filter { seen.insert($0).inserted }.prefix(HoverActions.capacity))
        }

        /// The actions not picked, in their usual order.
        public var unpicked: [SwipeChoice] { SwipeChoice.allCases.filter { !choices.contains($0) } }

        public var isFull: Bool { choices.count >= HoverActions.capacity }

        /// `choice` added last; unchanged when full.
        public func adding(_ choice: SwipeChoice) -> Picks { isFull ? self : Picks(choices + [choice]) }

        public func removing(_ choice: SwipeChoice) -> Picks { Picks(choices.filter { $0 != choice }) }

        /// The picks after a list move from `offsets` to `destination`, as `onMove` reports one.
        func moving(from offsets: IndexSet, to destination: Int) -> Picks {
            let moving = offsets.map { choices[$0] }
            var rest = choices.indices.filter { !offsets.contains($0) }.map { choices[$0] }
            rest.insert(contentsOf: moving, at: destination - offsets.count { $0 < destination })
            return Picks(rest)
        }
    }

    /// The buttons a row under the pointer shows for `thread` standing at `place`: each shown action whose swipe
    /// means something there, in its tint.
    func buttons(for thread: ThreadSummary, at place: ThreadPlace, tints: SwipeTints) -> [MailboxViewModel.SwipeButton]
    {
        shown.compactMap { choice in
            choice.swipe(for: thread, at: place).map {
                MailboxViewModel.SwipeButton(choice: choice, swipe: $0, tint: tints[choice])
            }
        }
    }
}
