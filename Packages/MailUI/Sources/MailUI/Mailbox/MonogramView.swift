import UIKit

/// A neutral gray circle with the sender's initials, and an optional account-colored badge on its top corner.
final class MonogramView: UIView {
    static let diameter: CGFloat = 40
    private static let badgeDiameter: CGFloat = 12

    private let initials = UILabel()
    private let badge = UIView()

    init() {
        super.init(frame: .zero)
        backgroundColor = .tertiarySystemFill
        layer.cornerRadius = Self.diameter / 2

        initials.font = UIFont.systemFont(ofSize: 15, weight: .semibold).rounded
        initials.textColor = .secondaryLabel
        initials.textAlignment = .center
        badge.layer.cornerRadius = Self.badgeDiameter / 2
        badge.layer.borderWidth = 2
        badge.layer.borderColor = UIColor.systemBackground.cgColor

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
            view.badge.layer.borderColor = UIColor.systemBackground.resolvedColor(with: view.traitCollection).cgColor
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }

    func configure(name: String, badge color: UIColor?) {
        initials.text = Monogram.initials(for: name)
        badge.backgroundColor = color
        badge.isHidden = color == nil
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
