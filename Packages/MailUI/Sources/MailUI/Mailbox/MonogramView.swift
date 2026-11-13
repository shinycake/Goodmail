import UIKit

/// A neutral gray circle with the sender's initials, and an optional account-colored badge on its top corner.
final class MonogramView: UIView {
    /// The account's mark: a dot for unread mail, or a quieter ring for read mail in a view spanning accounts.
    enum Badge: Equatable {
        case dot(UIColor)
        case ring(UIColor)
    }

    static let diameter: CGFloat = 40
    private static let badgeDiameter: CGFloat = 12

    private let initials = UILabel()
    private let badge = UIView()

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
        badge.layer.cornerRadius = Self.badgeDiameter / 2

        for view in [initials, badge] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Self.diameter),
            heightAnchor.constraint(equalToConstant: Self.diameter),
            initials.centerXAnchor.constraint(equalTo: centerXAnchor),
            initials.centerYAnchor.constraint(equalTo: centerYAnchor),
            badge.widthAnchor.constraint(equalToConstant: Self.badgeDiameter),
            badge.heightAnchor.constraint(equalToConstant: Self.badgeDiameter),
            badge.topAnchor.constraint(equalTo: topAnchor, constant: -1),
            badge.trailingAnchor.constraint(equalTo: trailingAnchor, constant: 1),
        ])
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: MonogramView, _) in
            view.applyBadge()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }

    private var shownBadge: Badge?

    func configure(name: String, badge: Badge?) {
        initials.text = Monogram.initials(for: name)
        shownBadge = badge
        applyBadge()
    }

    /// Layer colors don't follow the appearance, so they are resolved again when it changes.
    private func applyBadge() {
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

nonisolated enum Monogram {
    /// Up to two initials from the first letters of the first two words: "Dana Levi" → "DL", "יעל כהן" → "יכ".
    static func initials(for name: String) -> String {
        let words = name.split { $0.isWhitespace || $0 == "@" || $0 == "." }
        let letters = words.prefix(2).compactMap { $0.first(where: \.isLetter) }
        return String(letters).uppercased()
    }
}

extension UIFont {
    var rounded: UIFont {
        fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: pointSize) } ?? self
    }
}
