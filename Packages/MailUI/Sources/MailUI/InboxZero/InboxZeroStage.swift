import CoreGraphics

/// Where the Inbox Zero scene's envelopes and doodles are: the doodles' field, in whatever space it was measured in,
/// and the envelopes inside it. The paper plane game takes over from here and folds back to here.
nonisolated struct InboxZeroStage: Equatable, Sendable {
    /// The doodles' field: the envelopes and the words with room around them.
    private(set) var field: CGRect
    /// The middle of the envelopes at rest, in the field.
    let focus: CGPoint
    let pileWidth: CGFloat
    /// Whether the ring of doodles is drawn around the envelopes.
    let isDecorated: Bool

    /// The coordinate space of the whole of `InboxZeroView`, which fills the view hosting it, safe areas included.
    static let space = "inboxZero"

    /// The stage of a field laid out `layout`'s way, with envelopes `pileWidth` wide at the top of its halo.
    init(field: CGRect, layout: InboxZeroLayout, pileWidth: CGFloat) {
        self.field = field
        focus = CGPoint(x: field.width / 2, y: layout.haloAbove + pileWidth * EnvelopeLayer.aspect / 2)
        self.pileWidth = pileWidth
        isDecorated = layout.isDecorated
    }

    /// The envelopes at rest, in the field: the only place a tap counts toward the game.
    var pile: CGRect {
        let height = pileWidth * EnvelopeLayer.aspect
        return CGRect(x: focus.x - pileWidth / 2, y: focus.y - height / 2, width: pileWidth, height: height)
    }

    /// The middle of the envelopes in the space the field was measured in.
    var center: CGPoint { CGPoint(x: field.minX + focus.x, y: field.minY + focus.y) }

    /// The same stage with its field measured in another space, as `convert` turns a rectangle into it.
    func converted(_ convert: (CGRect) -> CGRect) -> InboxZeroStage {
        var stage = self
        stage.field = convert(field)
        return stage
    }
}

/// What the Inbox Zero scene hands the game when the tenth tap lands: what it drew in that frame, and where.
nonisolated struct InboxZeroHandoff: Equatable, Sendable {
    /// The scene as the frame drew it: the envelopes' pose, the doodles' drift and the planes in the air.
    let scene: DoodleScene
    let stage: InboxZeroStage
}
