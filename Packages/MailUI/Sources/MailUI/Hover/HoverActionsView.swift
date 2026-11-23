import UIKit

/// A small capsule of buttons tucked into the upper trailing corner of a row under the pointer, in the time's place.
/// Each button does one quick action on that row alone and carries a tooltip with its name and keys. VoiceOver and the
/// keyboard reach the same actions through the row's rotor and context menu, so the capsule stays out of both.
///
/// It holds at most `HoverActions.capacity` buttons, which always fit, so it is placed by hand at its own size.
final class HoverActionsView: UIView {
    static let buttonSide: CGFloat = 20
    static let spacing: CGFloat = 1
    /// Between the capsule's edge and its buttons.
    static let padding: CGFloat = 1

    let buttons: [HoverActionButton]
    private let material = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))

    init(actions: [HoverAction]) {
        buttons = actions.map(HoverActionButton.init)
        super.init(frame: .zero)
        accessibilityElementsHidden = true
        material.clipsToBounds = true
        material.layer.cornerCurve = .continuous
        addSubview(material)
        for button in buttons { material.contentView.addSubview(button) }
        layer.shadowOffset = CGSize(width: 0, height: 0.5)
        layer.shadowRadius = 1.5
        registerForTraitChanges([UITraitUserInterfaceStyle.self, UITraitDisplayScale.self]) {
            (view: HoverActionsView, _) in view.setNeedsLayout()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }

    override var intrinsicContentSize: CGSize {
        let count = CGFloat(buttons.count)
        return CGSize(
            width: 2 * Self.padding + count * Self.buttonSide + max(count - 1, 0) * Self.spacing,
            height: 2 * Self.padding + Self.buttonSide)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        material.frame = bounds
        material.layer.cornerRadius = bounds.height / 2
        // A hairline and the faintest shadow set the capsule apart from the row's tint without drawing the eye.
        material.layer.borderWidth = 1 / traitCollection.displayScale
        material.layer.borderColor = UIColor.separator.resolvedColor(with: traitCollection).cgColor
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = traitCollection.userInterfaceStyle == .dark ? 0.25 : 0.08
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: bounds.height / 2).cgPath
        let side = Self.buttonSide
        let leftToRight = effectiveUserInterfaceLayoutDirection == .leftToRight
        for (index, button) in buttons.enumerated() {
            let leading = Self.padding + CGFloat(index) * (side + Self.spacing)
            let x = leftToRight ? leading : bounds.width - leading - side
            button.frame = CGRect(x: x, y: (bounds.height - side) / 2, width: side, height: side)
        }
    }
}

/// One quick action's button: an 11.5 point glyph in the secondary label color on a 20 point face. Under the pointer
/// the face takes a light fill and the glyph lights up in the action's own color, as Mail's do.
final class HoverActionButton: ConfiguredButton {
    private let face: HoverAction.Face
    /// Whether the pointer is over the button, which `UIButton` doesn't track itself.
    var isUnderPointer = false {
        didSet { if isUnderPointer != oldValue { setNeedsUpdateConfiguration() } }
    }

    init(_ action: HoverAction) {
        face = action.face
        super.init(frame: .zero)
        var configuration = UIButton.Configuration.plain()
        // The image carries its size itself. Given only the preferred configuration, a button on the Mac sized the
        // glyph at the body size, then squeezed it into the face's whole height, cut off at the capsule's edge. The
        // preferred configuration stays so any image the button resolves later keeps the same size.
        let glyph = UIImage.SymbolConfiguration(pointSize: 11.5, weight: .medium, scale: .medium)
        configuration.image = UIImage(systemName: face.symbol, withConfiguration: glyph)
        configuration.preferredSymbolConfigurationForImage = glyph
        configuration.contentInsets = .zero
        configuration.cornerStyle = .capsule
        configuration.baseForegroundColor = .secondaryLabel
        self.configuration = configuration
        toolTip = face.tooltip
        addAction(UIAction { _ in action.run() }, for: .primaryActionTriggered)
        addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(hovered)))
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
