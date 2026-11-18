import CoreGraphics

/// How much of the Inbox Zero scene the space allows: all of it, a tighter version on a short screen like an iPhone
/// SE's, the doodles beside the envelopes rather than around them in a space too low for a ring but wide enough, such
/// as a landscape iPhone's, or the envelopes and the words alone at accessibility text sizes and where the space is
/// both low and narrow.
nonisolated enum InboxZeroLayout: Equatable, Sendable {
    case full
    case short
    case flanked
    case bare

    /// The layout for `size`, the space between the title and the toolbar.
    init(size: CGSize, accessibilityText: Bool) {
        if accessibilityText {
            self = .bare
        } else if size.height >= 560 {
            self = .full
        } else if size.height >= 400 {
            self = .short
        } else if size.width >= Self.flankedWidth {
            self = .flanked
        } else {
            self = .bare
        }
    }

    /// The least width that fits doodles to both sides of the words.
    static let flankedWidth: CGFloat = 340

    /// How wide the envelopes are; `wide` is a regular-width column, where they grow.
    func pileWidth(wide: Bool) -> CGFloat {
        switch self {
        case .full: wide ? 240 : 200
        case .short: 168
        case .flanked, .bare: 132
        }
    }

    /// The room the doodles get above the envelopes.
    var haloAbove: CGFloat {
        switch self {
        case .full: 96
        case .short: 56
        case .flanked, .bare: 0
        }
    }

    /// The room the doodles get below the words.
    var haloBelow: CGFloat {
        switch self {
        case .full: 86
        case .short: 50
        case .flanked, .bare: 0
        }
    }

    /// Between the envelopes and the title.
    var gap: CGFloat { self == .full ? 22 : 16 }

    /// Whether doodles are drawn, ringed or beside the envelopes, and so whether paper planes fly from them and the
    /// doodles carry on into the pane beside the list.
    var hasDoodles: Bool { self != .bare }

    /// Whether the doodles are the ring around the envelopes, the one the paper plane game takes over and folds back
    /// into.
    var isRinged: Bool { self == .full || self == .short }

    /// The doodles around the envelopes: a ring, or two columns beside them.
    var doodles: [Doodle] { self == .flanked ? Doodle.inboxZeroFlanks : Doodle.inboxZero }
}
