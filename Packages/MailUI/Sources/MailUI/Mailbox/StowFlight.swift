import UIKit

/// Rows going into a box: the lid opens, each row lifts off the list as a card and arcs down into the box, shrinking
/// as it goes, and the lid drops shut. The cards fly in the render server; the main actor only sets them up.
enum StowFlight {
    static let opening: TimeInterval = 0.2
    static let flight: TimeInterval = 0.42
    static let closing: TimeInterval = 0.3
    /// The longest the last row waits behind the first, however many rows go in.
    static let maxStagger: TimeInterval = 0.24

    /// Flies `cells`' content into `box`, all within `container`, and calls `completion` once the lid is shut. The
    /// cells' content stays hidden afterwards, for the list to take the rows away.
    static func run(
        _ cells: [UICollectionViewCell], into box: StowBoxView, over container: UIView,
        completion: @escaping () -> Void
    ) {
        // Just under the lid, where the box opens.
        let target = box.convert(CGPoint(x: box.bounds.midX, y: box.bounds.height * 0.35), to: container)
        let cards = cells.map { lift($0, onto: container) }
        box.setOpen(true, duration: opening)
        let stagger = cards.count > 1 ? min(0.05, maxStagger / Double(cards.count - 1)) : 0
        let start = CACurrentMediaTime() + opening * 0.3
        CATransaction.begin()
        CATransaction.setCompletionBlock {
            for card in cards { card.removeFromSuperview() }
            shut(box, then: completion)
        }
        for (index, card) in cards.enumerated() {
            fly(card, to: target, at: start + Double(index) * stagger)
        }
        CATransaction.commit()
    }

    /// A card over `cell` showing its content, which the cell then hides.
    private static func lift(_ cell: UICollectionViewCell, onto container: UIView) -> UIView {
        let card = UIView(frame: cell.convert(cell.bounds, to: container))
        card.backgroundColor = .systemBackground
        card.layer.cornerRadius = 16
        card.layer.cornerCurve = .continuous
        card.layer.shadowColor = UIColor.black.cgColor
        card.layer.shadowOpacity = 0.18
        card.layer.shadowRadius = 12
        card.layer.shadowOffset = CGSize(width: 0, height: 4)
        card.isUserInteractionEnabled = false
        let content = cell.contentView
        let image = UIGraphicsImageRenderer(bounds: content.bounds).image { _ in
            content.drawHierarchy(in: content.bounds, afterScreenUpdates: false)
        }
        let picture = UIImageView(image: image)
        picture.frame = content.convert(content.bounds, to: cell)
        card.addSubview(picture)
        container.addSubview(card)
        content.alpha = 0
        return card
    }

    /// Lifts `card` up off its row, shrinking it clear of the buttons, then tosses it in an arc down into `target`,
    /// fading as it drops in.
    private static func fly(_ card: UIView, to target: CGPoint, at beginTime: CFTimeInterval) {
        let from = card.layer.position
        let lifted = CGPoint(x: from.x - card.bounds.width * 0.15, y: from.y - card.bounds.height * 0.75)
        let path = UIBezierPath()
        path.move(to: from)
        path.addLine(to: lifted)
        path.addQuadCurve(
            to: target,
            controlPoint: CGPoint(x: lifted.x + (target.x - lifted.x) * 0.6, y: min(lifted.y, target.y) - 40))
        let move = CAKeyframeAnimation(keyPath: "position")
        move.path = path.cgPath
        move.calculationMode = .paced
        let shrink = CAKeyframeAnimation(keyPath: "transform.scale")
        shrink.values = [1, 0.45, 0.04]
        shrink.keyTimes = [0, 0.3, 1]
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [1, 1, 0]
        fade.keyTimes = [0, 0.8, 1]

        let group = CAAnimationGroup()
        group.animations = [move, shrink, fade]
        group.duration = flight
        group.beginTime = card.layer.convertTime(beginTime, from: nil)
        group.fillMode = .backwards
        group.timingFunction = CAMediaTimingFunction(controlPoints: 0.45, 0, 0.6, 1)
        card.layer.position = target
        card.layer.opacity = 0
        card.layer.add(group, forKey: "stow")
    }

    /// Drops the lid and gives the box a small bump as the last row lands.
    private static func shut(_ box: StowBoxView, then completion: @escaping () -> Void) {
        // The lid settles on its own spring; only the bump times the end.
        box.setOpen(false, duration: closing)
        CATransaction.begin()
        CATransaction.setCompletionBlock(completion)
        let bump = CAKeyframeAnimation(keyPath: "transform.scale")
        bump.values = [1, 1.15, 1]
        bump.keyTimes = [0, 0.4, 1]
        bump.timingFunctions = [CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(name: .easeInEaseOut)]
        bump.duration = closing
        box.layer.add(bump, forKey: "bump")
        CATransaction.commit()
    }
}
