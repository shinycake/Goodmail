import MailCore
import UIKit

/// One laid-out draft: what it's called, who it's for, and how it starts.
final class DraftCard: UIView {
    /// The corner radius of a laid-out draft, which a picked one's composer starts from.
    static let cornerRadius: CGFloat = 28
    let id: Draft.ID
    var onOpen: (() -> Void)?
    var onClose: ((UIView) -> Void)?
    private let closeButton = UIButton(configuration: .gray())

    init(draft: Draft) {
        id = draft.id
        super.init(frame: .zero)
        backgroundColor = .draftCard
        layer.cornerRadius = Self.cornerRadius
        layer.cornerCurve = .continuous
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.25
        layer.shadowRadius = 16
        layer.shadowOffset = CGSize(width: 0, height: -2)

        let title = UILabel()
        title.text = draft.shelfTitle
        title.font = .preferredFont(forTextStyle: .headline)
        title.adjustsFontForContentSizeCategory = true
        closeButton.configuration?.image = UIImage(systemName: "xmark")
        closeButton.configuration?.cornerStyle = .capsule
        closeButton.configuration?.buttonSize = .mini
        closeButton.configuration?.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
            pointSize: 11, weight: .bold)
        closeButton.accessibilityLabel = String(
            localized: "Close \(draft.shelfTitle)", table: "Drafts", bundle: .module,
            comment: "VoiceOver: the close button of a minimized message; the argument is its title")
        closeButton.addAction(
            UIAction { [weak self] _ in
                guard let self else { return }
                onClose?(closeButton)
            }, for: .primaryActionTriggered)
        closeButton.setContentHuggingPriority(.required, for: .horizontal)
        closeButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        title.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let header = UIStackView(arrangedSubviews: [title, closeButton])
        header.alignment = .center
        header.spacing = 8

        let to = UILabel()
        to.attributedText = Self.recipientsLine(draft)
        to.adjustsFontForContentSizeCategory = true
        let separator = UIView()
        separator.backgroundColor = .separator
        separator.heightAnchor.constraint(equalToConstant: 1 / 3).isActive = true
        let preview = UILabel()
        preview.text = draft.shelfPreview
        preview.font = .preferredFont(forTextStyle: .subheadline)
        preview.adjustsFontForContentSizeCategory = true
        preview.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [header, to, separator, preview, UIView()])
        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -16),
        ])
        clipsToBounds = false

        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(open)))
        isAccessibilityElement = false
        shouldGroupAccessibilityChildren = true
        title.accessibilityTraits = [.button, .header]
        title.accessibilityHint = String(
            localized: "Opens the message.", table: "Drafts", bundle: .module,
            comment: "VoiceOver hint of the drafts pill holding one message, and of a laid-out draft")
        accessibilityIdentifier = "drafts.card"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }

    private static func recipientsLine(_ draft: Draft) -> NSAttributedString {
        let font = UIFont.preferredFont(forTextStyle: .subheadline)
        let line = NSMutableAttributedString(
            string: String(localized: "To:", table: "Drafts", bundle: .module, comment: "Before who a draft goes to")
                + " ",
            attributes: [.font: font, .foregroundColor: UIColor.secondaryLabel])
        line.append(
            NSAttributedString(
                string: draft.shelfRecipients, attributes: [.font: font, .foregroundColor: UIColor.tintColor]))
        return line
    }

    @objc private func open() {
        onOpen?()
    }
}

nonisolated extension UIColor {
    /// A laid-out draft: lifted off the dimmed mail screens in both themes.
    static let draftCard = UIColor { traits in
        traits.userInterfaceStyle == .dark ? .tertiarySystemBackground : .systemBackground
    }
}
