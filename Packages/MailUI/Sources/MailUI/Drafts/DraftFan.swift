import CoreGraphics

/// The geometry of the laid-out drafts coming out of the pill and going back into it.
nonisolated enum DraftFan {
    /// How much later each card behind the front one starts than the one in front of it.
    static let step = 0.05
    /// How much later, at most, the last card starts than the front one.
    static let spread = 0.25

    /// The transform that tucks a card at `card` into the pill at `pill`: scaled to the pill's width about the card's
    /// centre, its centre on the pill's.
    static func tucked(_ card: CGRect, into pill: CGRect) -> CGAffineTransform {
        let scale = card.width > 0 ? pill.width / card.width : 1
        return CGAffineTransform(translationX: pill.midX - card.midX, y: pill.midY - card.midY)
            .scaledBy(x: scale, y: scale)
    }

    /// How far into the motion the card `index` places behind the front one, of `count`, starts: `step` each, closer
    /// together when there are so many that the last would start after `spread`.
    static func delay(behind index: Int, of count: Int) -> Double {
        guard count > 1 else { return 0 }
        return Double(index) * min(step, spread / Double(count - 1))
    }
}
