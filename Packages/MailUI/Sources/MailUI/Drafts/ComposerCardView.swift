import UIKit

/// The card the composer is written in, over the mail screens. Its grabber shows it can be pulled down into the
/// drafts pill. As it goes, the card's shape shrinks and the composer inside is scaled to its width, never squeezed,
/// so what shows is always the top of the live composer. Near the pill the whole card thins out as one group.
///
/// The card is one surface colour, resolved at the elevated level as a sheet's is, so the grabber's strip and the
/// composer below it match.
final class ComposerCardView: UIView {
    /// The corner radius while the card fills the screen.
    static let openCornerRadius: CGFloat = 38
    /// How far the composer starts below the card's top, leaving the grabber its room.
    static let grabberRoom: CGFloat = 12
    /// How far the open card reaches below the screen, so its bottom corners are rounded off screen and all four
    /// can stay round as it shrinks.
    static let overhang = openCornerRadius

    /// Casts the shadow. A view of its own with no sublayers, so typing in the composer never makes Core Animation
    /// draw the shadow again.
    private let backing = UIView()
    /// The card's shape, which clips the scaled composer.
    private let clip = UIView()
    /// The composer and the grabber at the size they have open, scaled to the card's width.
    private let cover = UIView()
    private let grabber = Grabber()
    /// The size the composer has with the card open.
    private var openSize = CGSize.zero

    /// Moves the message to the pill: the grabber's VoiceOver action.
    var onMinimize: (() -> Void)? {
        get { grabber.onMinimize }
        set { grabber.onMinimize = newValue }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        // As a sheet is: lifted off the screen behind it. The composer inherits it through the views.
        traitOverrides.userInterfaceLevel = .elevated
        // VoiceOver stays in the message while it's open, as it would in a sheet.
        accessibilityViewIsModal = true
        backing.backgroundColor = .systemBackground
        backing.layer.shadowColor = UIColor.black.cgColor
        backing.layer.shadowOpacity = 0.16
        backing.layer.shadowRadius = 20
        backing.layer.shadowOffset = CGSize(width: 0, height: 8)
        clip.clipsToBounds = true
        cover.backgroundColor = .systemBackground
        backing.layer.cornerCurve = .continuous
        clip.layer.cornerCurve = .continuous
        addSubview(backing)
        addSubview(clip)
        clip.addSubview(cover)
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

    /// Holds the composer's view at the size it has open, `openSize` being the open card's: as the card shrinks it
    /// is scaled with it rather than squeezed.
    func hold(_ composerView: UIView, openSize: CGSize) {
        self.openSize = openSize
        cover.bounds = CGRect(origin: .zero, size: openSize)
        composerView.autoresizingMask = []
        composerView.frame = CGRect(
            x: 0, y: Self.grabberRoom, width: openSize.width,
            height: openSize.height - Self.overhang - Self.grabberRoom)
        if composerView.superview !== cover { cover.insertSubview(composerView, belowSubview: grabber) }
        fit(frame, cornerRadius: clip.layer.cornerRadius)
    }

    /// Puts the card at `frame`, the composer scaled to its width and never above its open size, its top on the
    /// card's top. Every change here is linear in an animator's progress, so it is animatable.
    func fit(_ frame: CGRect, cornerRadius: CGFloat) {
        self.frame = frame
        let bounds = CGRect(origin: .zero, size: frame.size)
        backing.frame = bounds
        clip.frame = bounds
        backing.layer.cornerRadius = cornerRadius
        clip.layer.cornerRadius = cornerRadius
        let scale = openSize.width > 0 ? min(frame.width / openSize.width, 1) : 1
        cover.transform = CGAffineTransform(scaleX: scale, y: scale)
        cover.center = CGPoint(x: frame.width / 2, y: openSize.height * scale / 2)
    }

    /// Fits the card at `frame` by way of a frame one point narrower, so the composer's layout is solved again
    /// rather than kept from where an animator left it.
    func refit(_ frame: CGRect, cornerRadius: CGFloat) {
        fit(frame.insetBy(dx: 1, dy: 0), cornerRadius: cornerRadius)
        fit(frame, cornerRadius: cornerRadius)
    }
}

/// The capsule at the top of the card. To VoiceOver it's a button that minimizes the message, as big as a button
/// needs to be to find; to a finger it's part of the card, which takes the drag.
private final class Grabber: UIView {
    /// Room enough for VoiceOver to land on, with the capsule at its top.
    static let size = CGSize(width: 88, height: 44)
    private static let capsuleTop: CGFloat = 6
    private static let capsuleSize = CGSize(width: 36, height: 5)
    var onMinimize: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        let capsule = UIView()
        capsule.backgroundColor = .tertiaryLabel
        capsule.layer.cornerRadius = Self.capsuleSize.height / 2
        capsule.translatesAutoresizingMaskIntoConstraints = false
        addSubview(capsule)
        NSLayoutConstraint.activate([
            capsule.topAnchor.constraint(equalTo: topAnchor, constant: Self.capsuleTop),
            capsule.centerXAnchor.constraint(equalTo: centerXAnchor),
            capsule.widthAnchor.constraint(equalToConstant: Self.capsuleSize.width),
            capsule.heightAnchor.constraint(equalToConstant: Self.capsuleSize.height),
        ])
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityIdentifier = "compose.grabber"
        accessibilityLabel = String(
            localized: "Minimize", table: "Drafts", bundle: .module,
            comment:
                "VoiceOver: the grabber at the top of the composer, which minimizes the message into the drafts pill")
        accessibilityHint = String(
            localized: "Puts the message aside to come back to.", table: "Drafts", bundle: .module,
            comment: "VoiceOver hint of the composer's grabber, which minimizes the message into the drafts pill")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }

    override func accessibilityActivate() -> Bool {
        onMinimize?()
        return onMinimize != nil
    }
}
