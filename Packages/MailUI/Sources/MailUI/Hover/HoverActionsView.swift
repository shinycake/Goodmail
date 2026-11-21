import UIKit

/// A small glass group of buttons that takes the time's place on a row under the pointer. Each button does one quick
/// action on that row alone and carries a tooltip with its name and keys. VoiceOver and the keyboard reach the same
/// actions through the row's rotor and context menu, so the group stays out of both.
final class HoverActionsView: UIVisualEffectView {
    init(actions: [HoverAction]) {
        let glass = UIGlassEffect()
        glass.isInteractive = true
        super.init(effect: glass)
        cornerConfiguration = .capsule()
        accessibilityElementsHidden = true
        let buttons = actions.map(Self.button)
        let stack = UIStackView(arrangedSubviews: buttons)
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -4),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }

    private static func button(for action: HoverAction) -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: action.face.symbol)
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
            pointSize: 13, weight: .medium)
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 5, leading: 7, bottom: 5, trailing: 7)
        configuration.baseForegroundColor = action.face.isDestructive ? .systemRed : .label
        let button = UIButton(
            configuration: configuration,
            primaryAction: UIAction { _ in action.run() })
        button.toolTip = action.face.tooltip
        button.setContentHuggingPriority(.required, for: .horizontal)
        return button
    }
}
