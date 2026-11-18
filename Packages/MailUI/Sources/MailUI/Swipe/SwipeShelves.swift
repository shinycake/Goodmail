/// The choices the swipe settings list shows on each shelf, in order. Unlike an arrangement, it takes a drop exactly
/// where it fell, whether or not the arrangement would: a fourth action on a side, or More Actions out of their usual
/// order. The list moves a dropped row before it reports the drop, so its data has to match that until the drag ends.
nonisolated struct SwipeShelves: Equatable, Sendable {
    private var left: [SwipeChoice]
    private var right: [SwipeChoice]
    private var unused: [SwipeChoice]

    init(_ arrangement: SwipeArrangement) {
        left = arrangement.left
        right = arrangement.right
        unused = arrangement.unused
    }

    subscript(shelf: SwipeArrangement.Shelf) -> [SwipeChoice] {
        get {
            switch shelf {
            case .side(.left): left
            case .side(.right): right
            case .unused: unused
            }
        }
        set {
            switch shelf {
            case .side(.left): left = newValue
            case .side(.right): right = newValue
            case .unused: unused = newValue
            }
        }
    }

    /// Takes `choices` off their shelves and puts them on `shelf` in their order, before `anchor` or last, as the list
    /// does. A drop before one of its own choices changes nothing, as in the arrangement.
    mutating func drop(_ choices: [SwipeChoice], on shelf: SwipeArrangement.Shelf, before anchor: SwipeChoice?) {
        if let anchor, choices.contains(anchor) { return }
        left.removeAll(where: choices.contains)
        right.removeAll(where: choices.contains)
        unused.removeAll(where: choices.contains)
        let placed = self[shelf]
        self[shelf].insert(contentsOf: choices, at: anchor.flatMap(placed.firstIndex) ?? placed.endIndex)
    }
}

/// What the swipe settings list shows: the arrangement, or a drop the arrangement refused or reordered, shown where it
/// fell until its drag ends. Then the list goes back to the arrangement as an ordinary change it animates, as when a
/// remove button takes an action off. Changing the data inside the drop crashed UIKit, whose row counts had already
/// taken the drop.
nonisolated enum SwipeListState: Equatable, Sendable {
    case following
    case showingDrop(SwipeShelves)

    /// The shelves the list shows in place of the arrangement's, while there is one.
    var shownShelves: SwipeShelves? {
        switch self {
        case .following: nil
        case .showingDrop(let shelves): shelves
        }
    }

    /// Makes the drop the list reported: in `arrangement` where the arrangement takes it, and as it fell in what the
    /// list shows.
    mutating func drop(
        _ choices: [SwipeChoice], on shelf: SwipeArrangement.Shelf, before anchor: SwipeChoice?,
        into arrangement: inout SwipeArrangement
    ) {
        var shown = shownShelves ?? SwipeShelves(arrangement)
        shown.drop(choices, on: shelf, before: anchor)
        arrangement.move(choices, to: shelf, before: anchor)
        self = shown == SwipeShelves(arrangement) ? .following : .showingDrop(shown)
    }

    mutating func dragEnded() {
        self = .following
    }
}
