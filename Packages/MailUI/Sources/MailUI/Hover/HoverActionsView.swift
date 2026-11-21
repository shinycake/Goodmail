import UIKit

/// A small glass capsule of buttons that takes the time's place on a row under the pointer. Each button does one quick
/// action on that row alone and carries a tooltip with its name and keys. VoiceOver and the keyboard reach the same
/// actions through the row's rotor and context menu, so the group stays out of both.
final class HoverActionsView: UIVisualEffectView {
    init(actions: [HoverAction]) {
        let glass = UIGlassEffect()
        glass.isInteractive = true
        super.init(effect: glass)
        cornerConfiguration = .capsule()
        accessibilityElementsHidden = true
        let stack = UIStackView(arrangedSubviews: actions.map(HoverActionButton.init))
        stack.spacing = 2
        stack.distribution = .equalSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 1),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -1),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -4),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }
}

/// One quick action's button: a 13 point glyph in the secondary label color that lights up in the action's own color
/// while the pointer is on it or it is pressed, as Mail's do.
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
        configuration.image = UIImage(systemName: face.symbol)
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 3, leading: 5, bottom: 3, trailing: 5)
        configuration.baseForegroundColor = .secondaryLabel
        self.configuration = configuration
        addAction(UIAction { _ in action.run() }, for: .primaryActionTriggered)
        toolTip = face.tooltip
        setContentHuggingPriority(.required, for: .horizontal)
        addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(hovered)))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }

    override func updateConfiguration() {
        super.updateConfiguration()
        configuration?.baseForegroundColor = isUnderPointer || isHighlighted ? face.color : .secondaryLabel
    }

    @objc private func hovered(_ recognizer: UIHoverGestureRecognizer) {
        isUnderPointer = recognizer.state == .began || recognizer.state == .changed
    }
}
