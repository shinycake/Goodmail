import MailCore
import UIKit

/// The minimized messages laid out as overlapping cards, the last one written in front, to pick one to go back to.
final class DraftPickerViewController: UIViewController {
    var onChoose: ((Draft.ID) -> Void)?
    /// The close button on a card, with the button to anchor what it asks.
    var onClose: ((Draft.ID, UIView) -> Void)?
    var onDismiss: (() -> Void)?
    var onNewMessage: (() -> Void)?
    private var drafts: [Draft]
    private let scrollView = UIScrollView()
    private let cards = UIStackView()
    /// How much of each card behind shows above the next.
    private static let peek: CGFloat = 150
    private static let cardHeight: CGFloat = 300

    /// `drafts` is the last one written first.
    init(entries drafts: [Draft]) {
        self.drafts = drafts
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }

    override func viewDidLoad() {
        super.viewDidLoad()
        let dimming = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
        dimming.frame = view.bounds
        dimming.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        dimming.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(dismissTapped)))
        view.addSubview(dimming)

        scrollView.alwaysBounceVertical = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.backgroundColor = .clear
        let background = UITapGestureRecognizer(target: self, action: #selector(dismissTapped))
        background.cancelsTouchesInView = false
        scrollView.addGestureRecognizer(background)
        view.addSubview(scrollView)
        cards.axis = .vertical
        cards.spacing = Self.peek - Self.cardHeight
        cards.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(cards)

        let newMessage = UIButton(configuration: .glass())
        newMessage.configuration?.title = String(
            localized: "New Message", table: "Compose", bundle: .module, comment: "Composer title")
        newMessage.configuration?.image = UIImage(systemName: "plus")
        newMessage.configuration?.imagePadding = 6
        newMessage.configuration?.buttonSize = .large
        newMessage.accessibilityIdentifier = "drafts.new"
        newMessage.addAction(UIAction { [weak self] _ in self?.onNewMessage?() }, for: .primaryActionTriggered)
        newMessage.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(newMessage)

        let readable = view.readableContentGuide
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: newMessage.topAnchor, constant: -12),
            cards.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 16),
            cards.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -16),
            cards.leadingAnchor.constraint(equalTo: readable.leadingAnchor),
            cards.trailingAnchor.constraint(equalTo: readable.trailingAnchor),
            // Few cards sit at the bottom, near the bar they came from.
            cards.heightAnchor.constraint(
                greaterThanOrEqualTo: scrollView.frameLayoutGuide.heightAnchor, constant: -32),
            newMessage.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            newMessage.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
        ])
        show(drafts)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard !hasScrolled, scrollView.contentSize.height > 0 else { return }
        hasScrolled = true
        // The front card, the last one written, starts in view.
        let bottom = scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom
        scrollView.contentOffset.y = max(-scrollView.adjustedContentInset.top, bottom)
    }

    private var hasScrolled = false

    /// Lays out `drafts`, the last one written first, which goes in front at the bottom.
    func show(_ drafts: [Draft]) {
        self.drafts = drafts
        for card in cards.arrangedSubviews { card.removeFromSuperview() }
        // A spacer pushes few cards to the bottom.
        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow, for: .vertical)
        cards.addArrangedSubview(spacer)
        cards.setCustomSpacing(0, after: spacer)
        for draft in drafts.reversed() {
            cards.addArrangedSubview(card(for: draft))
        }
    }

    private func card(for draft: Draft) -> UIView {
        let card = DraftCard(draft: draft)
        card.heightAnchor.constraint(equalToConstant: Self.cardHeight).isActive = true
        card.onOpen = { [weak self] in self?.onChoose?(draft.id) }
        card.onClose = { [weak self] button in self?.onClose?(draft.id, button) }
        return card
    }

    @objc private func dismissTapped(_ recognizer: UITapGestureRecognizer) {
        // Taps on a card open it; only the space around them goes back.
        let point = recognizer.location(in: cards)
        guard !cards.arrangedSubviews.contains(where: { $0 is DraftCard && $0.frame.contains(point) }) else { return }
        onDismiss?()
    }

    override func accessibilityPerformEscape() -> Bool {
        onDismiss?()
        return true
    }
}

/// One laid-out draft: what it's called, who it's for, and how it starts.
private final class DraftCard: UIView {
    var onOpen: (() -> Void)?
    var onClose: ((UIView) -> Void)?
    private let closeButton = UIButton(configuration: .gray())

    init(draft: Draft) {
        super.init(frame: .zero)
        backgroundColor = .shelfCard
        layer.cornerRadius = 28
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
            comment: "VoiceOver hint of the bar holding one minimized message")
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
