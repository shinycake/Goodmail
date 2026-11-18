import UIKit

/// What's behind the composer's open card: the mail screens dimmed, and on a narrow window a curtain over the strip
/// above the card, where the screens' top buttons would otherwise show around its corners. A wide window's card sits
/// below those buttons, so it has no curtain.
final class ComposerBackdropView: UIView {
    private let curtain = UIView()
    private let scrim = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        // The screens' own background, which the scrim then dims as it does the rest.
        curtain.backgroundColor = .systemBackground
        scrim.backgroundColor = UIColor.black.withAlphaComponent(0.3)
        for layer in [curtain, scrim] {
            layer.frame = bounds
            addSubview(layer)
        }
        scrim.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }

    /// Covers the top of the screen down to `bottom`, or nothing when `bottom` is `nil`.
    func curtain(down bottom: CGFloat?) {
        curtain.isHidden = bottom == nil
        curtain.frame = CGRect(x: 0, y: 0, width: bounds.width, height: bottom ?? 0)
    }

    /// How much the screens are dimmed. Animatable.
    var dimming: CGFloat {
        get { scrim.alpha }
        set { scrim.alpha = newValue }
    }

    /// How much the curtain is drawn. Animatable.
    var curtainAlpha: CGFloat {
        get { curtain.alpha }
        set { curtain.alpha = newValue }
    }
}
