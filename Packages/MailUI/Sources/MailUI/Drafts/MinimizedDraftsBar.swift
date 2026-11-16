import MailCore
import UIKit

/// The bar under the mail screens that holds minimized messages, with the others peeking out behind it. Swiping up
/// or tapping opens them.
final class MinimizedDraftsBar: UIView {
    /// The bar's least height above the bottom safe area; larger text makes it taller.
    static let height: CGFloat = 54
    var onOpen: (() -> Void)?
    private let card = UIView()
    /// Edges of the other messages behind the front one, at most two.
    private let behind = [UIView(), UIView()]
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let grabber = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        for (index, edge) in behind.enumerated().reversed() {
            edge.backgroundColor = index == 0 ? .shelfEdge : .shelfFarEdge
            edge.layer.cornerRadius = 30
            edge.layer.cornerCurve = .continuous
            edge.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
            edge.translatesAutoresizingMaskIntoConstraints = false
            addSubview(edge)
            let inset = CGFloat(index + 1) * 10
            NSLayoutConstraint.activate([
                edge.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
                edge.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
                edge.bottomAnchor.constraint(equalTo: bottomAnchor),
                edge.topAnchor.constraint(equalTo: topAnchor, constant: -CGFloat(index + 1) * 6),
            ])
        }
        card.backgroundColor = .shelfCard
        card.layer.cornerRadius = 30
        card.layer.cornerCurve = .continuous
        card.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        card.translatesAutoresizingMaskIntoConstraints = false
        addSubview(card)

        grabber.backgroundColor = .tertiaryLabel
        grabber.layer.cornerRadius = 2.5
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textAlignment = .center
        detailLabel.font = .preferredFont(forTextStyle: .caption1)
        detailLabel.adjustsFontForContentSizeCategory = true
        detailLabel.textColor = .secondaryLabel
        detailLabel.textAlignment = .center
        // The bar grows with the text, up to where it would crowd out the mail screens above it.
        for label in [titleLabel, detailLabel] {
            label.maximumContentSizeCategory = .accessibilityLarge
            // Both lines show: the bar grows rather than squeezing one away.
            label.setContentCompressionResistancePriority(.required, for: .vertical)
            label.lineBreakMode = .byTruncatingTail
        }
        let stack = UIStackView(arrangedSubviews: [titleLabel, detailLabel])
        stack.axis = .vertical
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        grabber.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(grabber)
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: leadingAnchor),
            card.trailingAnchor.constraint(equalTo: trailingAnchor),
            card.topAnchor.constraint(equalTo: topAnchor),
            card.bottomAnchor.constraint(equalTo: bottomAnchor),
            grabber.topAnchor.constraint(equalTo: card.topAnchor, constant: 6),
            grabber.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            grabber.widthAnchor.constraint(equalToConstant: 36),
            grabber.heightAnchor.constraint(equalToConstant: 5),
            stack.topAnchor.constraint(equalTo: grabber.bottomAnchor, constant: 4),
            stack.leadingAnchor.constraint(equalTo: card.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: card.layoutMarginsGuide.trailingAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: card.safeAreaLayoutGuide.bottomAnchor, constant: -4),
        ])

        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(open)))
        let swipe = UISwipeGestureRecognizer(target: self, action: #selector(open))
        swipe.direction = .up
        addGestureRecognizer(swipe)
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityIdentifier = "drafts.bar"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }

    /// Shows `drafts`, the last one written first.
    func show(_ drafts: [Draft]) {
        guard let front = drafts.first else { return }
        for (index, edge) in behind.enumerated() { edge.isHidden = drafts.count <= index + 1 }
        if drafts.count == 1 {
            titleLabel.text = front.shelfTitle
            detailLabel.text = front.shelfRecipients
        } else {
            titleLabel.text = String(
                localized: "\(drafts.count) Drafts", table: "Drafts", bundle: .module,
                comment: "The bar holding several minimized messages")
            detailLabel.text = [front.shelfTitle, front.shelfRecipients].filter { !$0.isEmpty }.joined(separator: " · ")
        }
        detailLabel.isHidden = detailLabel.text?.isEmpty ?? true
        accessibilityLabel = [titleLabel.text, detailLabel.isHidden ? nil : detailLabel.text].compactMap(\.self)
            .joined(separator: ", ")
        accessibilityHint =
            drafts.count == 1
            ? String(
                localized: "Opens the message.", table: "Drafts", bundle: .module,
                comment: "VoiceOver hint of the bar holding one minimized message")
            : String(
                localized: "Shows the drafts to pick one.", table: "Drafts", bundle: .module,
                comment: "VoiceOver hint of the bar holding several minimized messages")
    }

    @objc private func open() {
        onOpen?()
    }

    override func accessibilityActivate() -> Bool {
        open()
        return true
    }
}

extension UIColor {
    /// A minimized message: lifted off the mail screens' background in both themes.
    static let shelfCard = UIColor { traits in
        traits.userInterfaceStyle == .dark ? .tertiarySystemBackground : .systemBackground
    }

    /// The edge of the message just behind the front one.
    fileprivate static let shelfEdge = UIColor { traits in
        traits.userInterfaceStyle == .dark ? .systemGray4 : .systemGray3
    }

    /// The edge of the message behind that.
    fileprivate static let shelfFarEdge = UIColor { traits in
        traits.userInterfaceStyle == .dark ? .systemGray5 : .systemGray4
    }
}
