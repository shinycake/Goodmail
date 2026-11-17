import MailCore
import UIKit

/// The sender's picture, or their initials on a neutral gray circle when there is none, and an optional
/// account-colored badge on its top corner. Without the monogram, the badge stands alone in a narrow column.
final class MonogramView: UIView {
    /// The account's mark: a dot for unread mail, or a quieter ring for read mail in a view spanning accounts.
    enum Badge: Equatable {
        case dot(UIColor)
        case ring(UIColor)
    }

    static let diameter: CGFloat = 40
    private static let badgeDiameter: CGFloat = 12

    private let initials = UILabel()
    private let picture = UIImageView()
    private let badge = UIView()
    private let pictureBinding = SenderPictureBinding()
    /// Whose picture to show; `nil` while the monogram is hidden.
    private var address: String?
    private var size: [NSLayoutConstraint] = []
    /// The badge overhangs the monogram's corner by this much, and sits flush when it stands alone.
    private static let badgeOverhang: CGFloat = 1
    private lazy var badgeTop = badge.topAnchor.constraint(equalTo: topAnchor, constant: -Self.badgeOverhang)
    private lazy var badgeTrailing = badge.trailingAnchor.constraint(
        equalTo: trailingAnchor, constant: Self.badgeOverhang)

    /// How wide the view is, with or without its monogram.
    static func width(showingMonogram: Bool) -> CGFloat {
        showingMonogram ? diameter : badgeDiameter
    }

    init() {
        super.init(frame: .zero)
        backgroundColor = .tertiarySystemFill
        layer.cornerRadius = Self.diameter / 2

        // Decorative: the name sits beside it, so VoiceOver skips it, and the initials keep their size to fit the
        // fixed circle.
        accessibilityElementsHidden = true
        initials.font = UIFont.systemFont(ofSize: 15, weight: .semibold).rounded
        initials.textColor = .secondaryLabel
        initials.textAlignment = .center
        initials.accessibilityIdentifier = "avatar.initials"
        badge.layer.cornerRadius = Self.badgeDiameter / 2
        picture.contentMode = .scaleAspectFill
        picture.clipsToBounds = true
        picture.layer.cornerRadius = Self.diameter / 2
        picture.isHidden = true
        picture.layer.borderWidth = 1 / 3
        // A photo, which Smart Invert would turn into a negative.
        picture.accessibilityIgnoresInvertColors = true

        for view in [initials, picture, badge] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        size = [
            widthAnchor.constraint(equalToConstant: Self.diameter),
            heightAnchor.constraint(equalToConstant: Self.diameter),
        ]
        NSLayoutConstraint.activate(
            size + [
                badgeTop, badgeTrailing,
                initials.centerXAnchor.constraint(equalTo: centerXAnchor),
                initials.centerYAnchor.constraint(equalTo: centerYAnchor),
                picture.leadingAnchor.constraint(equalTo: leadingAnchor),
                picture.trailingAnchor.constraint(equalTo: trailingAnchor),
                picture.topAnchor.constraint(equalTo: topAnchor),
                picture.bottomAnchor.constraint(equalTo: bottomAnchor),
                badge.widthAnchor.constraint(equalToConstant: Self.badgeDiameter),
                badge.heightAnchor.constraint(equalToConstant: Self.badgeDiameter),
            ])
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: MonogramView, _) in
            view.applyBadge()
        }
        // The window's pictures arrive once the view is in it.
        registerForTraitChanges([SenderPicturesTrait.self]) { (view: MonogramView, _) in
            view.bindPicture()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }

    private var shownBadge: Badge?

    /// Shows `address`'s picture when there is one, else `name`'s initials.
    func configure(name: String, address: String?, badge: Badge?, showingMonogram: Bool = true) {
        initials.text = Monogram.initials(for: name)
        shownBadge = badge
        self.address = showingMonogram ? address : nil
        applyMonogram(showingMonogram)
        applyBadge()
        bindPicture()
    }

    private func bindPicture() {
        pictureBinding.bind(address: address, pictures: traitCollection.senderPictures) { [weak self] image in
            self?.showPicture(image)
        }
    }

    /// The picture covers the initials, which stay for when it goes.
    private func showPicture(_ image: UIImage?) {
        picture.image = image
        picture.isHidden = image == nil
    }

    private func applyMonogram(_ shown: Bool) {
        let side = Self.width(showingMonogram: shown)
        for constraint in size { constraint.constant = side }
        // A badge on its own fills the view rather than overhanging its corner.
        let overhang = shown ? Self.badgeOverhang : 0
        badgeTop.constant = -overhang
        badgeTrailing.constant = overhang
        layer.cornerRadius = side / 2
        backgroundColor = shown ? .tertiarySystemFill : .clear
        initials.isHidden = !shown
    }

    /// Layer colors don't follow the appearance, so they are resolved again when it changes.
    private func applyBadge() {
        // A hairline edge, so a logo on white doesn't float in a light row and a dark logo keeps its shape on a
        // dark one.
        picture.layer.borderColor = UIColor.separator.resolvedColor(with: traitCollection).cgColor
        let background = UIColor.systemBackground.resolvedColor(with: traitCollection)
        badge.isHidden = shownBadge == nil
        switch shownBadge {
        case nil: break
        case .dot(let color):
            badge.backgroundColor = color
            badge.layer.borderColor = background.cgColor
            badge.layer.borderWidth = 2
        case .ring(let color):
            badge.backgroundColor = background
            badge.layer.borderColor = color.resolvedColor(with: traitCollection).cgColor
            badge.layer.borderWidth = 2.5
        }
    }
}

extension UIFont {
    var rounded: UIFont {
        fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: pointSize) } ?? self
    }
}
