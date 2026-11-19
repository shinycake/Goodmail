import MailCore
import UIKit

/// The minimized messages: a glass capsule in the middle of the bottom toolbar, between Search and Compose, or above
/// the toolbar where there's no room in it. It names the last message written, or how many there are. Dragging up
/// brings them up under the finger; tapping opens them. The composer's card ends its minimize as one of these.
final class DraftPillView: UIView {
    /// The capsule's height, a toolbar button's.
    static let height: CGFloat = 48
    var onOpen: (() -> Void)?
    /// A drag up began; whoever opens the messages follows `pan` from here.
    var onDrag: ((UIPanGestureRecognizer) -> Void)?
    private let glass = UIVisualEffectView(effect: UIGlassEffect())
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private lazy var labels = UIStackView(arrangedSubviews: [titleLabel, detailLabel])

    /// How much of what the capsule says shows; the glass always does, as it can't fade. Animatable.
    var labelsAlpha: CGFloat {
        get { labels.alpha }
        set { labels.alpha = newValue }
    }

    /// A capsule that takes taps and drags, or, on the composer's card, one only to look at.
    init(interactive: Bool) {
        super.init(frame: CGRect(x: 0, y: 0, width: 200, height: Self.height))
        glass.cornerConfiguration = .capsule()
        glass.frame = bounds
        glass.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(glass)
        titleLabel.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(
            for: .systemFont(ofSize: 15, weight: .semibold))
        detailLabel.font = .preferredFont(forTextStyle: .caption2)
        detailLabel.textColor = .secondaryLabel
        for label in [titleLabel, detailLabel] {
            label.adjustsFontForContentSizeCategory = true
            // The capsule keeps a toolbar button's height; past this, pressing and holding shows it large.
            label.maximumContentSizeCategory = .extraExtraLarge
            label.textAlignment = .center
            label.lineBreakMode = .byTruncatingTail
        }
        let stack = labels
        stack.axis = .vertical
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        glass.contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: glass.contentView.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: glass.contentView.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: glass.contentView.trailingAnchor, constant: -18),
        ])
        isUserInteractionEnabled = interactive
        guard interactive else {
            accessibilityElementsHidden = true
            return
        }
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(open)))
        addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(dragged)))
        showsLargeContentViewer = true
        addInteraction(UILargeContentViewerInteraction())
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityIdentifier = "drafts.bar"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }

    /// Shows `drafts`, the last one written first.
    func show(_ drafts: [Draft]) {
        guard let front = drafts.first else { return }
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
        largeContentTitle = accessibilityLabel
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

    @objc private func dragged(_ pan: UIPanGestureRecognizer) {
        if pan.state == .began { onDrag?(pan) }
    }

    /// Only a drag that heads up opens the messages.
    override func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
        guard let pan = recognizer as? UIPanGestureRecognizer, pan.view === self else {
            return super.gestureRecognizerShouldBegin(recognizer)
        }
        let velocity = pan.velocity(in: self)
        return velocity.y < 0 && abs(velocity.y) > abs(velocity.x)
    }

    override func accessibilityActivate() -> Bool {
        open()
        return true
    }
}
