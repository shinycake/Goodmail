import CoreGraphics

/// How many of a row's quick actions its capsule shows in the room the row gives it. Every button keeps its full size;
/// the capsule shows the first actions that fit and, when some don't, ends with a More button that holds the rest.
nonisolated struct HoverFit: Equatable {
    static let buttonSide: CGFloat = 28
    static let spacing: CGFloat = 2
    /// Between the capsule's edge and its first and last buttons, and above and below them.
    static let padding: CGFloat = 3

    /// The actions offered, in priority order.
    let total: Int
    /// How many of them show, from the front; the rest are under More.
    let shown: Int

    var overflows: Bool { shown < total }
    /// The buttons drawn, More included.
    var buttons: Int { shown + (overflows ? 1 : 0) }
    var size: CGSize {
        let count = CGFloat(buttons)
        return CGSize(
            width: 2 * Self.padding + count * Self.buttonSide + max(count - 1, 0) * Self.spacing,
            height: 2 * Self.padding + Self.buttonSide)
    }

    init(actions total: Int, room: CGFloat) {
        self.total = total
        // Anything wider than a screen holds every action; clamping keeps the count finite.
        let room = min(max(room, 0), 10_000)
        let slots = max(
            1, Int(((room - 2 * Self.padding + Self.spacing) / (Self.buttonSide + Self.spacing)).rounded(.down)))
        shown = slots >= total ? total : slots - 1
    }
}
