import UIKit

/// The card the composer is written in, over the mail screens. Its grabber shows it can be pulled down to the bar,
/// which the card shrinks into as it goes.
final class ComposerCardView: UIView {
    /// The corner radius while the card fills the screen.
    static let openCornerRadius: CGFloat = 38
    /// How far the composer starts below the card's top, leaving the grabber its room.
    static let grabberRoom: CGFloat = 12
    /// What the composer's content sits in, so it can fade without the card and grabber.
    let content = UIView()
    private let grabber = Grabber()
    /// Moves the message to the bar: the grabber's VoiceOver action.
    var onMinimize: (() -> Void)? {
        get { grabber.onMinimize }
        set { grabber.onMinimize = newValue }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .shelfCard
        layer.cornerCurve = .continuous
        layer.cornerRadius = Self.openCornerRadius
        layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        clipsToBounds = true
        // VoiceOver stays in the message while it's open, as it would in a sheet.
        accessibilityViewIsModal = true
        content.frame = bounds
        addSubview(content)
        grabber.translatesAutoresizingMaskIntoConstraints = false
        addSubview(grabber)
        NSLayoutConstraint.activate([
            grabber.topAnchor.constraint(equalTo: topAnchor),
            grabber.centerXAnchor.constraint(equalTo: centerXAnchor),
            grabber.widthAnchor.constraint(equalToConstant: Grabber.size.width),
            grabber.heightAnchor.constraint(equalToConstant: Grabber.size.height),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }

    /// The composer's view, kept at the size it has open: as the card shrinks into the bar it clips the composer
    /// rather than squeezing it.
    func hold(_ composerView: UIView, openSize: CGSize) {
        composerView.frame = CGRect(
            x: (bounds.width - openSize.width) / 2, y: Self.grabberRoom, width: openSize.width,
            height: openSize.height - Self.grabberRoom)
        composerView.autoresizingMask = [.flexibleLeftMargin, .flexibleRightMargin, .flexibleBottomMargin]
        content.frame = bounds
        content.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        content.addSubview(composerView)
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
