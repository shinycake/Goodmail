import CoreGraphics

/// The side of a row a swipe uncovers, on screen.
nonisolated enum SwipeSide: Equatable, Sendable {
    case left, right

    /// The side a drag heading `dx` uncovers: moving left uncovers the right, as if the row slid.
    init(heading dx: CGFloat) {
        self = dx < 0 ? .right : .left
    }

    /// +1 when a rightward drag reveals more, −1 when a leftward one does.
    var towardEdge: CGFloat { self == .left ? 1 : -1 }
}

/// Where the list's one swipe stands. The row is carried by identity, so the state follows the row wherever the list
/// moves it, and a drag on the open row only ever moves its own buttons.
nonisolated enum SwipeState<Row: Identifiable> {
    /// No row shows its actions.
    case idle
    /// A drag is moving `row`'s buttons on `side`; they were revealed `start` points when it began.
    case dragging(Row, SwipeSide, start: CGFloat)
    /// `row`'s buttons rest fully revealed on `side`, `width` points in from the edge.
    case open(Row, SwipeSide, width: CGFloat)

    /// How a drag ended.
    enum End {
        /// Far enough to fire `row`'s edge-most action.
        case fired(Row)
        /// Past halfway: the buttons settle open `width` points in.
        case opened(Row, width: CGFloat)
        /// Short of halfway, or cancelled: the buttons slide away.
        case closed(Row)
    }

    var row: Row? {
        switch self {
        case .idle: nil
        case .dragging(let row, _, _), .open(let row, _, _): row
        }
    }

    /// A drag begins on the row `id`, heading `dx`. On the open row it picks the buttons up where they rest, whichever
    /// way it heads, so dragging back can only close them. Anywhere else it reveals the side it heads to, with the row
    /// `reveal` makes for that side, or nothing when that side has no actions.
    ///
    /// Returns the row whose buttons the drag took over from, for the caller to take off screen.
    mutating func begin(on id: Row.ID, heading dx: CGFloat, reveal: (SwipeSide) -> Row?) -> Row? {
        if case .open(let row, let side, let width) = self, row.id == id {
            self = .dragging(row, side, start: width)
            return nil
        }
        let previous = row
        let side = SwipeSide(heading: dx)
        self = reveal(side).map { .dragging($0, side, start: 0) } ?? .idle
        return previous
    }

    /// How far the dragged buttons are revealed once the finger has moved `dx` from where the drag began. Never
    /// below zero: pulling past closed doesn't cross over to the other side.
    func distance(afterMoving dx: CGFloat) -> CGFloat? {
        guard case .dragging(_, let side, let start) = self else { return nil }
        return max(0, start + side.towardEdge * dx)
    }

    /// The drag lets go after moving `dx`, at horizontal `velocity`, with buttons laid out by `layout`.
    mutating func end(afterMoving dx: CGFloat, velocity: CGFloat, layout: SwipeLayout, cancelled: Bool) -> End? {
        guard case .dragging(let row, let side, _) = self, let distance = distance(afterMoving: dx) else { return nil }
        if !cancelled, layout.reveal(at: distance).isFullSwipe {
            self = .idle
            return .fired(row)
        }
        if !cancelled, distance + side.towardEdge * velocity * 0.15 > layout.revealWidth / 2 {
            self = .open(row, side, width: layout.revealWidth)
            return .opened(row, width: layout.revealWidth)
        }
        self = .idle
        return .closed(row)
    }

    /// Hides whatever shows. Returns the row that showed its actions.
    mutating func close() -> Row? {
        defer { self = .idle }
        return row
    }
}

nonisolated extension SwipeState: Equatable where Row: Equatable {}
nonisolated extension SwipeState.End: Equatable where Row: Equatable {}
