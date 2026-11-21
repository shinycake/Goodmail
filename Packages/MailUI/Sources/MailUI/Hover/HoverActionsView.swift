import UIKit

/// A capsule of buttons that floats over the trailing end of a row under the pointer. Each button does one quick action
/// on that row alone and carries a tooltip with its name and keys. VoiceOver and the keyboard reach the same actions
/// through the row's rotor and context menu, so the capsule stays out of both.
///
/// The row says how much room it gives (`room`). The capsule shows the first actions that fit at full size and, when
/// some don't, a More button whose menu holds the rest (`HoverFit`). Buttons are placed by hand rather than by a stack
/// view, whose compression would shrink them before the capsule gave up any width.
final class HoverActionsView: UIView {
    /// The most width the row lets the capsule take.
    var room: CGFloat = .greatestFiniteMagnitude {
        didSet { if room != oldValue { refit() } }
    }

    private(set) var fit: HoverFit
    private let actions: [HoverAction]
    private let buttons: [HoverActionButton]
    private let more = HoverActionButton(face: .more)
    private let material = UIVisualEffectView(effect: UIBlurEffect(style: .systemThickMaterial))

    init(actions: [HoverAction]) {
        self.actions = actions
        buttons = actions.map(HoverActionButton.init)
        fit = HoverFit(actions: actions.count, room: .greatestFiniteMagnitude)
        super.init(frame: .zero)
        accessibilityElementsHidden = true
        material.clipsToBounds = true
        material.layer.cornerCurve = .continuous
        addSubview(material)
        for button in buttons + [more] { material.contentView.addSubview(button) }
        more.showsMenuAsPrimaryAction = true
        layer.shadowOffset = CGSize(width: 0, height: 1)
        layer.shadowRadius = 5
        show(fit)
        registerForTraitChanges([UITraitUserInterfaceStyle.self, UITraitDisplayScale.self]) {
            (view: HoverActionsView, _) in view.setNeedsLayout()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }

    override var intrinsicContentSize: CGSize { fit.size }

    /// The buttons drawn, More last when it shows, in reading order.
    var shownButtons: [HoverActionButton] {
        Array(buttons.prefix(fit.shown)) + (fit.overflows ? [more] : [])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        material.frame = bounds
        material.layer.cornerRadius = bounds.height / 2
        // A hairline and a soft shadow lift the capsule off the row's own tint, in light and dark alike.
        material.layer.borderWidth = 1 / traitCollection.displayScale
        material.layer.borderColor = UIColor.separator.resolvedColor(with: traitCollection).cgColor
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = traitCollection.userInterfaceStyle == .dark ? 0.4 : 0.14
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: bounds.height / 2).cgPath
        let side = HoverFit.buttonSide
        let leftToRight = effectiveUserInterfaceLayoutDirection == .leftToRight
        for (index, button) in shownButtons.enumerated() {
            let leading = HoverFit.padding + CGFloat(index) * (side + HoverFit.spacing)
            let x = leftToRight ? leading : bounds.width - leading - side
            button.frame = CGRect(x: x, y: (bounds.height - side) / 2, width: side, height: side)
        }
    }

    private func refit() {
        let new = HoverFit(actions: actions.count, room: room)
        guard new != fit else { return }
        fit = new
        show(new)
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    private func show(_ fit: HoverFit) {
        for (index, button) in buttons.enumerated() { button.isHidden = index >= fit.shown }
        more.isHidden = !fit.overflows
        more.menu = UIMenu(
            children: actions.dropFirst(fit.shown).map { action in
                UIAction(title: action.face.title, image: UIImage(systemName: action.face.symbol)) { _ in action.run() }
            })
    }
}

/// One quick action's button: a 14 point glyph in the secondary label color on a 28 point face. Under the pointer the
/// face takes a light fill and the glyph lights up in the action's own color, as Mail's do.
final class HoverActionButton: ConfiguredButton {
    private let face: HoverAction.Face
    /// Whether the pointer is over the button, which `UIButton` doesn't track itself.
    var isUnderPointer = false {
        didSet { if isUnderPointer != oldValue { setNeedsUpdateConfiguration() } }
    }

    init(face: HoverAction.Face) {
        self.face = face
        super.init(frame: .zero)
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: face.symbol)
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        configuration.contentInsets = .zero
        configuration.cornerStyle = .capsule
        configuration.baseForegroundColor = .secondaryLabel
        self.configuration = configuration
        toolTip = face.tooltip
        addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(hovered)))
    }

    convenience init(_ action: HoverAction) {
        self.init(face: action.face)
        addAction(UIAction { _ in action.run() }, for: .primaryActionTriggered)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }

    override func updateConfiguration() {
        super.updateConfiguration()
        let lit = isUnderPointer || isHighlighted
        configuration?.baseForegroundColor = lit ? face.color : .secondaryLabel
        configuration?.background.backgroundColor = lit ? .tertiarySystemFill : .clear
    }

    @objc private func hovered(_ recognizer: UIHoverGestureRecognizer) {
        isUnderPointer = recognizer.state == .began || recognizer.state == .changed
    }
}
