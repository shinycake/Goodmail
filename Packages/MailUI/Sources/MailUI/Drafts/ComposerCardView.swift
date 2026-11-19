import MailCore
import UIKit

/// The card the composer is written in, over the mail screens. Pulled down, it shrinks into the bar of minimized
/// messages under the mail screens: the composer itself scales down with the card, then gives way to the bar it
/// becomes, grabber on grabber.
///
/// Two layers: the `face`, the same bar as the minimized messages, and over it the `cover`, which holds the
/// composer at its open size and the grabber. The cover scales with the card's width, its top at the card's top, so
/// the composer fills the card's width at every moment of the motion and the card clips what falls below.
final class ComposerCardView: UIView {
    /// The corner radius while the card fills the screen.
    static let openCornerRadius: CGFloat = 38
    /// How far the composer starts below the card's top, leaving the grabber its room.
    static let grabberRoom: CGFloat = 12
    /// How far the card reaches past the bottom of the screen, open or as the bar, so only its top corners show round.
    static let overhang = openCornerRadius
    /// The bar the card becomes, under the composer.
    let face = MinimizedDraftsBar(interactive: false)
    /// The composer at its open size, and the grabber, over the face.
    private let cover = UIView()
    private let grabber = Grabber()
    /// The cover's size, the card's when open.
    private var openSize = CGSize.zero
    /// Moves the message to the bar: the grabber's VoiceOver action.
    var onMinimize: (() -> Void)? {
        get { grabber.onMinimize }
        set { grabber.onMinimize = newValue }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerCurve = .continuous
        layer.cornerRadius = Self.openCornerRadius
        clipsToBounds = true
        // VoiceOver stays in the message while it's open, as it would in a sheet.
        accessibilityViewIsModal = true
        face.frame = bounds
        face.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(face)
        // One surface from the grabber down, lifted off the screen behind it as a sheet is.
        cover.backgroundColor = .systemBackground
        cover.traitOverrides.userInterfaceLevel = .elevated
        addSubview(cover)
        grabber.translatesAutoresizingMaskIntoConstraints = false
        cover.addSubview(grabber)
        NSLayoutConstraint.activate([
            grabber.topAnchor.constraint(equalTo: cover.topAnchor),
            grabber.centerXAnchor.constraint(equalTo: cover.centerXAnchor),
            grabber.widthAnchor.constraint(equalToConstant: Grabber.size.width),
            grabber.heightAnchor.constraint(equalToConstant: Grabber.size.height),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }

    /// Takes the composer's view, kept at the size it has open, `openSize` less the overhang: as the card shrinks the
    /// composer scales with it rather than squeezing.
    func hold(_ composerView: UIView, openSize: CGSize) {
        self.openSize = openSize
        cover.transform = .identity
        cover.bounds = CGRect(origin: .zero, size: openSize)
        composerView.frame = CGRect(
            x: 0, y: Self.grabberRoom, width: openSize.width,
            height: openSize.height - Self.overhang - Self.grabberRoom)
        composerView.autoresizingMask = []
        cover.insertSubview(composerView, belowSubview: grabber)
    }

    /// Puts the card at `frame` with corners of `cornerRadius`, the composer scaled to its width. Animatable.
    func fit(_ frame: CGRect, cornerRadius: CGFloat) {
        self.frame = frame
        layer.cornerRadius = cornerRadius
        let scale = openSize.width > 0 ? frame.width / openSize.width : 1
        cover.transform = CGAffineTransform(scaleX: scale, y: scale)
        cover.center = CGPoint(x: frame.width / 2, y: openSize.height * scale / 2)
        face.layoutIfNeeded()
    }

    /// Puts the card back at `frame` once a motion has run back to it. The animator puts its start back beneath the
    /// views, where Auto Layout doesn't see it: it still has the card where the motion was headed, and with it the
    /// composer's keyboard guide, which would squeeze the message into what's left above the bar. Setting the same
    /// frame again changes nothing it sees, so the card passes through another one first.
    func refit(_ frame: CGRect, cornerRadius: CGFloat) {
        fit(frame.insetBy(dx: 1, dy: 0), cornerRadius: cornerRadius)
        fit(frame, cornerRadius: cornerRadius)
    }

    /// How much of the composer shows over the face. Animatable.
    var composerAlpha: CGFloat {
        get { cover.alpha }
        set {
            cover.alpha = newValue
        }
    }
}

/// The capsule at the top of the card. To VoiceOver it's a button that minimizes the message, as big as a button
/// needs to be to find; to a finger it's part of the card, which takes the drag.
private final class Grabber: UIView {
    /// Room enough for VoiceOver to land on, with the capsule at its top.
    static let size = CGSize(width: 88, height: 44)
    var onMinimize: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        let capsule = UIView()
        capsule.backgroundColor = .tertiaryLabel
        capsule.layer.cornerRadius = MinimizedDraftsBar.grabberSize.height / 2
        capsule.translatesAutoresizingMaskIntoConstraints = false
        addSubview(capsule)
        NSLayoutConstraint.activate([
            capsule.topAnchor.constraint(equalTo: topAnchor, constant: MinimizedDraftsBar.grabberTop),
            capsule.centerXAnchor.constraint(equalTo: centerXAnchor),
            capsule.widthAnchor.constraint(equalToConstant: MinimizedDraftsBar.grabberSize.width),
            capsule.heightAnchor.constraint(equalToConstant: MinimizedDraftsBar.grabberSize.height),
        ])
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityIdentifier = "compose.grabber"
        accessibilityLabel = String(
            localized: "Minimize", table: "Drafts", bundle: .module,
            comment: "VoiceOver: the grabber at the top of the composer, which moves the message down to the bar")
        accessibilityHint = String(
            localized: "Keeps the message at the bottom of the screen to come back to.", table: "Drafts",
            bundle: .module, comment: "VoiceOver hint of the composer's grabber")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }

    override func accessibilityActivate() -> Bool {
        onMinimize?()
        return onMinimize != nil
    }
}
