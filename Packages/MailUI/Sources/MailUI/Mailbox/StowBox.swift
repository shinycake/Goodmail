import UIKit

/// Where an action puts a thread away, drawn as a box whose lid opens to take the row in.
nonisolated enum StowKind: Sendable {
    case trash, archive
}

/// A trash can or archive box drawn in strokes like its SF Symbol, with a lid that swings open on its hinge. It
/// stands in for the symbol on a button while rows go into it.
final class StowBoxView: UIView {
    let kind: StowKind
    private let body = CAShapeLayer()
    private let lid = CAShapeLayer()
    /// The design grid the strokes are drawn on, scaled to the view.
    private static let grid: CGFloat = 24
    /// How far the lid swings up, in radians, away from its hinge.
    private static let openAngle: CGFloat = -0.75

    init(kind: StowKind, color: UIColor) {
        self.kind = kind
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        for shape in [body, lid] {
            shape.fillColor = nil
            shape.lineCap = .round
            shape.lineJoin = .round
            shape.strokeColor = color.cgColor
            layer.addSublayer(shape)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let scale = min(bounds.width, bounds.height) / Self.grid
        let origin = CGPoint(
            x: (bounds.width - Self.grid * scale) / 2, y: (bounds.height - Self.grid * scale) / 2)
        var place = CGAffineTransform(translationX: origin.x, y: origin.y).scaledBy(x: scale, y: scale)
        let paths = Self.paths(for: kind)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (shape, path) in [(body, paths.body), (lid, paths.lid)] {
            // Bounds and position rather than frame: the lid may be turned, and a turned layer has no frame.
            shape.bounds = bounds
            shape.position = CGPoint(x: bounds.midX, y: bounds.midY)
            shape.lineWidth = 1.9 * scale
            shape.path = path.copy(using: &place)
        }
        lidHinge = paths.hinge.applying(place)
        CATransaction.commit()
    }

    /// Where the lid turns, in the view's coordinates.
    private var lidHinge = CGPoint.zero

    /// Swings the lid open or shut with a spring. Shutting it lands with a little bounce, as if the lid dropped.
    func setOpen(_ open: Bool, duration: TimeInterval) {
        let shut = CATransform3DIdentity
        let target = open ? hinged(Self.openAngle) : shut
        let spring = CASpringAnimation(perceptualDuration: duration, bounce: open ? 0.1 : Motion.bounce(0.35))
        spring.keyPath = "transform"
        spring.fromValue = lid.presentation()?.transform ?? lid.transform
        spring.toValue = target
        lid.transform = target
        lid.add(spring, forKey: "lid")
    }

    /// A turn of `angle` about the hinge rather than the layer's center.
    private func hinged(_ angle: CGFloat) -> CATransform3D {
        let fromCenter = CGPoint(x: lidHinge.x - bounds.midX, y: lidHinge.y - bounds.midY)
        var turn = CATransform3DMakeTranslation(fromCenter.x, fromCenter.y, 0)
        turn = CATransform3DRotate(turn, angle, 0, 0, 1)
        return CATransform3DTranslate(turn, -fromCenter.x, -fromCenter.y, 0)
    }

    /// The strokes on the 24-point grid: what stays put, what swings, and the corner the lid swings about.
    private static func paths(for kind: StowKind) -> (body: CGPath, lid: CGPath, hinge: CGPoint) {
        let body = CGMutablePath()
        let lid = CGMutablePath()
        switch kind {
        case .trash:
            // A tapered can with a rounded foot, under a flat lid with a handle.
            body.move(to: CGPoint(x: 5.5, y: 7.5))
            body.addLine(to: CGPoint(x: 6.7, y: 19.6))
            body.addQuadCurve(to: CGPoint(x: 8.7, y: 21.5), control: CGPoint(x: 6.9, y: 21.5))
            body.addLine(to: CGPoint(x: 15.3, y: 21.5))
            body.addQuadCurve(to: CGPoint(x: 17.3, y: 19.6), control: CGPoint(x: 17.1, y: 21.5))
            body.addLine(to: CGPoint(x: 18.5, y: 7.5))
            for x in [10.0, 14.0] {
                body.move(to: CGPoint(x: x, y: 10.5))
                body.addLine(to: CGPoint(x: x, y: 18.5))
            }
            lid.move(to: CGPoint(x: 3.5, y: 6))
            lid.addLine(to: CGPoint(x: 20.5, y: 6))
            lid.move(to: CGPoint(x: 9, y: 6))
            lid.addLine(to: CGPoint(x: 9, y: 4.2))
            lid.addQuadCurve(to: CGPoint(x: 10.2, y: 3), control: CGPoint(x: 9, y: 3))
            lid.addLine(to: CGPoint(x: 13.8, y: 3))
            lid.addQuadCurve(to: CGPoint(x: 15, y: 4.2), control: CGPoint(x: 15, y: 3))
            lid.addLine(to: CGPoint(x: 15, y: 6))
            return (body, lid, CGPoint(x: 3.5, y: 6))
        case .archive:
            // A box with a slot for a handle, under a wider lid.
            body.move(to: CGPoint(x: 4.5, y: 9.5))
            body.addLine(to: CGPoint(x: 4.5, y: 19))
            body.addQuadCurve(to: CGPoint(x: 6.5, y: 21), control: CGPoint(x: 4.5, y: 21))
            body.addLine(to: CGPoint(x: 17.5, y: 21))
            body.addQuadCurve(to: CGPoint(x: 19.5, y: 19), control: CGPoint(x: 19.5, y: 21))
            body.addLine(to: CGPoint(x: 19.5, y: 9.5))
            body.move(to: CGPoint(x: 9.5, y: 13.5))
            body.addLine(to: CGPoint(x: 14.5, y: 13.5))
            lid.addRoundedRect(in: CGRect(x: 2.5, y: 4, width: 19, height: 5.5), cornerWidth: 1.4, cornerHeight: 1.4)
            return (body, lid, CGPoint(x: 2.5, y: 9.5))
        }
    }
}

/// A disc of Liquid Glass holding a box, for when the action's own button is out of sight, as in the toolbar's
/// overflow menu. It pops in where the rows can reach it and goes once they are in.
final class StowBadgeView: UIVisualEffectView {
    let box: StowBoxView
    static let diameter: CGFloat = 64

    init(kind: StowKind) {
        let glass = UIGlassEffect(style: .regular)
        if kind == .trash { glass.tintColor = .systemRed.withAlphaComponent(0.8) }
        box = StowBoxView(kind: kind, color: kind == .trash ? .white : .label)
        super.init(effect: glass)
        cornerConfiguration = .capsule()
        isUserInteractionEnabled = false
        box.frame = CGRect(x: (Self.diameter - 32) / 2, y: (Self.diameter - 32) / 2, width: 32, height: 32)
        contentView.addSubview(box)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }

    /// Pops the badge in centered on `center` in `container`.
    func show(at center: CGPoint, in container: UIView) {
        bounds = CGRect(x: 0, y: 0, width: Self.diameter, height: Self.diameter)
        self.center = center
        container.addSubview(self)
        box.layoutIfNeeded()
        transform = CGAffineTransform(scaleX: 0.3, y: 0.3)
        alpha = 0
        UIView.animate(springDuration: StowFlight.opening, bounce: Motion.bounce(0.3)) {
            self.transform = .identity
            self.alpha = 1
        }
    }

    /// Shrinks the badge away and removes it.
    func dismiss() {
        UIView.animate(springDuration: 0.25, bounce: 0) {
            self.transform = CGAffineTransform(scaleX: 0.3, y: 0.3)
            self.alpha = 0
        } completion: { _ in
            self.removeFromSuperview()
        }
    }
}
