import MailUI
import UIKit

/// Covers the composer while its message goes: a glass card with a spinner, saying what is under way. Nothing under
/// it can be touched, so the message can't change or close while it is on its way.
final class ShareProgressView: UIView {
    init(_ errand: ShareSession.Errand) {
        super.init(frame: .zero)
        backgroundColor = UIColor.black.withAlphaComponent(0.15)
        let text =
            switch errand {
            case .send, .schedule:
                String(localized: "Sending…", comment: "Shown while a shared message goes")
            case .saveDraft:
                String(localized: "Saving…", comment: "Shown while a shared draft is saved")
            }

        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.startAnimating()
        let label = UILabel()
        label.text = text
        label.font = .preferredFont(forTextStyle: .headline)
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        let stack = UIStackView(arrangedSubviews: [spinner, label])
        stack.spacing = 12
        stack.alignment = .center

        let card = UIVisualEffectView(effect: UIGlassEffect())
        card.cornerConfiguration = .capsule()
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.contentView.addSubview(stack)
        card.translatesAutoresizingMaskIntoConstraints = false
        addSubview(card)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: card.contentView.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: card.contentView.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: card.contentView.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: card.contentView.bottomAnchor, constant: -16),
            card.centerXAnchor.constraint(equalTo: centerXAnchor),
            card.centerYAnchor.constraint(equalTo: centerYAnchor),
            card.leadingAnchor.constraint(greaterThanOrEqualTo: layoutMarginsGuide.leadingAnchor),
        ])

        isAccessibilityElement = true
        accessibilityLabel = text
        accessibilityTraits = .updatesFrequently
        accessibilityViewIsModal = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }

    func show(over view: UIView) {
        frame = view.bounds
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(self)
        SystemAccessibility.post(.screenChanged, argument: self)
    }
}
