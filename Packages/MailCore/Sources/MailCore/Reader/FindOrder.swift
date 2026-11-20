/// The order a find bar searches an open conversation's letters in, each letter being a web view of its own.
public enum FindOrder {
    public struct Attempt: Equatable, Sendable {
        public let view: Int
        /// Whether the search goes on from the match the letter already shows, rather than from its top or bottom.
        public let continuesSelection: Bool

        public init(view: Int, continuesSelection: Bool = false) {
            self.view = view
            self.continuesSelection = continuesSelection
        }
    }

    /// The letters to search, one after the other, until one has a match. `current` is the letter holding the match
    /// now, or `nil` for a new search. The letter that holds it goes on first, then the others in turn, and last that
    /// one again from its start, so a match before the current one is still found.
    public static func attempts(from current: Int?, count: Int, backwards: Bool) -> [Attempt] {
        let order = backwards ? Array((0..<count).reversed()) : Array(0..<count)
        guard let current, current >= 0, current < count, let at = order.firstIndex(of: current) else {
            return order.map { Attempt(view: $0) }
        }
        let others = order[(at + 1)...] + order[..<at]
        return [Attempt(view: current, continuesSelection: true)] + others.map { Attempt(view: $0) }
            + [Attempt(view: current)]
    }
}
