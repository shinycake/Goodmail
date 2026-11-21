import MailCore
import UIKit

/// The minimized messages laid out as overlapping cards, the last one written in front, to pick one to go back to. A
/// child of the shelf over the mail screens, not a modal: the cards come out of the drafts pill and go back into it.
final class DraftPickerViewController: UIViewController {
    var onChoose: ((Draft.ID) -> Void)?
    /// The close button on a card, with the button to anchor what it asks.
    var onClose: ((Draft.ID, UIView) -> Void)?
    var onDismiss: (() -> Void)?
    var onNewMessage: (() -> Void)?
    private var drafts: [Draft]
    private let dimming = UIVisualEffectView(effect: nil)
    private let scrollView = UIScrollView()
    private let cards = UIStackView()
    private let newMessage = ConfiguredButton(configuration: .glass())
    /// How much of each card behind shows above the next.
    private static let peek: CGFloat = 150
    private static let cardHeight: CGFloat = 300
    private static let blur = UIBlurEffect(style: .systemUltraThinMaterialDark)

    /// The cards' motion. Only `fanOut`, `fold` and `landed` change it.
    private var motion = Motion.tucked

    private enum Motion {
        /// In the pill, before they come out or once they are back.
        case tucked
        /// Coming out of the pill.
        case fanning(ScrubbedAnimation)
        /// Laid out and still.
        case laidOut
        /// Going back into it; `gone` runs once they are in.
        case folding(ScrubbedAnimation, gone: () -> Void)
    }

    private enum Timing {
        static let fan: TimeInterval = 0.45
        static let fold: TimeInterval = 0.4
    }

    /// The share of the fan over which each card comes up, and of the fold over which each goes clear.
    private static let fadeShare = 0.3
    /// How far into the fold a picked card starts to go clear: by then the composer growing out of it is nearly opaque.
    private static let pickedFadeStart = 0.4

    /// `drafts` is the last one written first.
    init(entries drafts: [Draft]) {
        self.drafts = drafts
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }

    override func viewDidLoad() {
        super.viewDidLoad()
        // The mail screens behind can't be reached while the drafts are laid out.
        view.accessibilityViewIsModal = true
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
            // Few cards sit at the bottom, near the pill they came from.
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

    /// The cards, the front one first.
    private var laidCards: [DraftCard] {
        cards.arrangedSubviews.compactMap { $0 as? DraftCard }.reversed()
    }

    /// Where `id`'s card is in `view`, at rest.
    func frame(of id: Draft.ID, in view: UIView) -> CGRect? {
        guard let card = laidCards.first(where: { $0.id == id }) else { return nil }
        return card.superview?.convert(card.frame, to: view)
    }

    // MARK: Out of the pill and back

    /// Brings the cards out of the pill at `pill`, in the view's coordinates. Call once the view is laid out.
    func fanOut(from pill: CGRect) {
        guard case .tucked = motion else { return }
        let laid = laidCards
        newMessage.transform = offBottom
        scrollView.clipsToBounds = false
        for card in laid {
            if !SystemAccessibility.reducesMotion { card.transform = tucked(card, into: pill) }
            card.alpha = 0
        }
        let animation = animation(duration: Timing.fan, blur: Self.blur) {
            UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 1) { self.newMessage.transform = .identity }
            for (index, card) in laid.enumerated() {
                let delay = DraftFan.delay(behind: index, of: laid.count)
                UIView.addKeyframe(withRelativeStartTime: delay, relativeDuration: 1 - delay) {
                    card.transform = .identity
                }
                UIView.addKeyframe(withRelativeStartTime: delay, relativeDuration: Self.fadeShare) { card.alpha = 1 }
            }
        }
        motion = .fanning(animation)
        animation.run(following: nil)
    }

    /// Sends the cards back into the pill at `pill`, all but `chosen`, which stays for the composer's card to grow
    /// over and goes clear in place once that card has come up over it: on a wide window the composer is narrower and
    /// wouldn't cover it. `gone` runs once they are in.
    func fold(into pill: CGRect, leaving chosen: Draft.ID? = nil, gone: @escaping () -> Void) {
        settleNow()
        guard case .laidOut = motion else { return gone() }
        view.isUserInteractionEnabled = false
        scrollView.clipsToBounds = false
        let folding = laidCards.filter { $0.id != chosen }
        let picked = laidCards.first { $0.id == chosen }
        let targets = folding.map { SystemAccessibility.reducesMotion ? .identity : tucked($0, into: pill) }
        let offBottom = offBottom
        let animation = animation(duration: Timing.fold, blur: nil) {
            UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 1) { self.newMessage.transform = offBottom }
            UIView.addKeyframe(withRelativeStartTime: Self.pickedFadeStart, relativeDuration: 1 - Self.pickedFadeStart)
            {
                picked?.alpha = 0
            }
            for (index, card) in folding.enumerated() {
                // The cards behind lead, so the front one goes in last, over them.
                let delay = DraftFan.delay(behind: folding.count - 1 - index, of: folding.count)
                UIView.addKeyframe(withRelativeStartTime: delay, relativeDuration: 1 - delay) {
                    card.transform = targets[index]
                }
                UIView.addKeyframe(withRelativeStartTime: 1 - Self.fadeShare, relativeDuration: Self.fadeShare) {
                    card.alpha = 0
                }
            }
        }
        motion = .folding(animation, gone: gone)
        animation.run(following: nil)
    }

    /// Ends a fan or a fold at once, at its end.
    func settleNow() {
        switch motion {
        case .fanning(let animation), .folding(let animation, _): animation.finishNow()
        case .tucked, .laidOut: break
        }
    }

    /// The fan or the fold came to rest, always at its end, as no finger drives either.
    private func landed() {
        switch motion {
        case .fanning:
            motion = .laidOut
            scrollView.clipsToBounds = true
            SystemAccessibility.post(.screenChanged, argument: laidCards.first)
        case .folding(_, let gone):
            motion = .tucked
            gone()
        case .tucked, .laidOut:
            break
        }
    }

    /// One critically damped motion of `keyframes`, with the blur going to `blur` alongside them.
    private func animation(duration: TimeInterval, blur: UIBlurEffect?, keyframes: @escaping () -> Void)
        -> ScrubbedAnimation
    {
        ScrubbedAnimation(
            distance: 0, heading: .up, in: view, duration: duration,
            animations: {
                self.dimming.effect = blur
                UIView.animateKeyframes(
                    withDuration: 0, delay: 0, options: [.calculationModeLinear], animations: keyframes)
            },
            landed: { [weak self] _ in self?.landed() })
    }

    /// The transform that tucks `card` into `pill`, in the view's coordinates.
    private func tucked(_ card: DraftCard, into pill: CGRect) -> CGAffineTransform {
        guard let superview = card.superview else { return .identity }
        return DraftFan.tucked(superview.convert(card.frame, to: view), into: pill)
    }

    /// New Message moved down off the bottom edge.
    private var offBottom: CGAffineTransform {
        CGAffineTransform(translationX: 0, y: view.bounds.maxY - newMessage.frame.minY)
    }

    // MARK: Going back

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
