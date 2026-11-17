import CoreGraphics

/// How much of the Inbox Zero scene the space allows: all of it, a tighter version on a short screen like an iPhone
/// SE's, or the envelopes and the words alone at accessibility text sizes and in a landscape iPhone's low space.
nonisolated enum InboxZeroLayout: Equatable, Sendable {
    case full
    case short
    case bare

    /// The layout for `height` points between the title and the toolbar.
    init(height: CGFloat, accessibilityText: Bool) {
        if accessibilityText || height < 400 {
            self = .bare
        } else if height < 560 {
            self = .short
        } else {
            self = .full
        }
    }

    /// How wide the envelopes are; `wide` is a regular-width column, where they grow.
    func pileWidth(wide: Bool) -> CGFloat {
        switch self {
        case .full: wide ? 240 : 200
        case .short: 168
        case .bare: 132
        }
    }

    /// The room the doodles get above the envelopes.
    var haloAbove: CGFloat {
        switch self {
        case .full: 96
        case .short: 56
        case .bare: 0
        }
    }

    /// The room the doodles get below the words.
    var haloBelow: CGFloat {
        switch self {
        case .full: 86
        case .short: 50
        case .bare: 0
        }
    }

    /// Between the envelopes and the title.
    var gap: CGFloat { self == .full ? 22 : 16 }

    /// Whether the doodles and paper planes are drawn.
    var isDecorated: Bool { self != .bare }
}
