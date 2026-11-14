import UIKit

/// Plays a `DissolveField` over a row that is leaving the list: one layer per tile, all sharing the row's image, each
/// driven by its own Core Animation group. The animations run in the render server, so the main actor only builds
/// the layers once and the dust stays smooth however busy the app is. The view removes itself when the last tile is
/// gone, and never takes touches.
final class DissolveView: UIView {
    /// The most tiles a dissolve shows at once, shared among the rows deleted together.
    static let particleBudget = 1800

    /// Breaks `cell`'s content into dust above it in `collectionView`, and hides the cell so the list can close the
    /// gap under the dust. Only the content is drawn into the dust, not the row's background, so no blank squares
    /// drift over the rows around it.
    @discardableResult
    static func dissolve(
        _ cell: UICollectionViewCell, in collectionView: UICollectionView, budget: Int = particleBudget,
        seed: UInt64 = .random(in: .min ... .max)
    ) -> DissolveView? {
        let content = cell.contentView
        let scale = collectionView.traitCollection.displayScale
        let format = UIGraphicsImageRendererFormat(for: collectionView.traitCollection)
        format.opaque = false
        let image = UIGraphicsImageRenderer(bounds: content.bounds, format: format).image { _ in
            content.drawHierarchy(in: content.bounds, afterScreenUpdates: false)
        }
        guard let cgImage = image.cgImage, let coverage = AlphaCoverage(cgImage, scale: scale) else { return nil }
        let isRightToLeft = collectionView.effectiveUserInterfaceLayoutDirection == .rightToLeft
        // The front starts at the trailing edge, where Delete sits.
        let field = DissolveField(
            size: content.bounds.size, budget: budget, from: isRightToLeft ? .left : .right, seed: seed,
            hasContent: coverage.hasContent)
        let view = DissolveView(frame: content.convert(content.bounds, to: collectionView))
        view.layer.zPosition = 20
        collectionView.addSubview(view)
        view.play(field, image: cgImage, scale: scale)
        cell.alpha = 0
        return view
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }

    private func play(_ field: DissolveField, image: CGImage, scale: CGFloat) {
        let size = bounds.size
        let start = layer.convertTime(CACurrentMediaTime(), from: nil)
        // Eases in, so each tile seems to break loose before it blows away.
        let loosen = CAMediaTimingFunction(controlPoints: 0.4, 0, 0.75, 0.55)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock { [weak self] in self?.removeFromSuperview() }
        for particle in field.particles {
            let tile = CALayer()
            tile.frame = particle.frame
            tile.contents = image
            tile.contentsScale = scale
            tile.contentsRect = CGRect(
                x: particle.frame.minX / size.width, y: particle.frame.minY / size.height,
                width: particle.frame.width / size.width, height: particle.frame.height / size.height)
            // Gone once its animation ends; shown as it is until the animation begins.
            tile.opacity = 0

            let move = CABasicAnimation(keyPath: "position")
            move.fromValue = tile.position
            move.toValue = CGPoint(x: tile.position.x + particle.drift.dx, y: tile.position.y + particle.drift.dy)
            let turn = CABasicAnimation(keyPath: "transform")
            turn.fromValue = CATransform3DIdentity
            turn.toValue = CATransform3DScale(
                CATransform3DMakeRotation(particle.rotation, 0, 0, 1), particle.scale, particle.scale, 1)
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 1
            fade.toValue = 0

            let group = CAAnimationGroup()
            group.animations = [move, turn, fade]
            group.duration = particle.lifetime
            group.beginTime = start + particle.delay
            group.fillMode = .backwards
            group.timingFunction = loosen
            tile.add(group, forKey: "dissolve")
            layer.addSublayer(tile)
        }
        CATransaction.commit()
    }
}

/// Which parts of an image have anything drawn, read once from its alpha channel.
private struct AlphaCoverage {
    private let alpha: [UInt8]
    private let width: Int
    private let height: Int
    private let scale: CGFloat
    /// Fainter than this is treated as empty, so antialiasing fringes don't each cost a tile.
    private static let threshold: UInt8 = 24

    init?(_ image: CGImage, scale: CGFloat) {
        let width = image.width
        let height = image.height
        // RGBA, since an alpha-only bitmap needs no color space and Swift's initializer insists on one.
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer in
            guard
                let context = CGContext(
                    data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                    bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        alpha = stride(from: 3, to: pixels.count, by: 4).map { pixels[$0] }
        self.width = width
        self.height = height
        self.scale = scale
    }

    /// Whether `rect`, in points from the image's top left, has any pixel drawn. Every other pixel is enough to tell.
    func hasContent(_ rect: CGRect) -> Bool {
        let minX = max(0, Int(rect.minX * scale))
        let maxX = min(width, Int((rect.maxX * scale).rounded(.up)))
        let minY = max(0, Int(rect.minY * scale))
        let maxY = min(height, Int((rect.maxY * scale).rounded(.up)))
        for y in stride(from: minY, to: maxY, by: 2) {
            let row = y * width
            for x in stride(from: minX, to: maxX, by: 2) where alpha[row + x] > Self.threshold {
                return true
            }
        }
        return false
    }
}
