import UIKit

/// A button drawn from its configuration on every device. Under the Mac idiom a plain `UIButton` takes the Mac's own
/// look instead: an accent-colored push button that ignores most of its configuration, draws a pop-up's chevrons
/// beside a menu button's own, and stands out among the toolbar's glyphs. Every button in MailUI is one of these, or
/// a subclass, which `scripts/configured-buttons` checks.
class ConfiguredButton: UIButton {
    override init(frame: CGRect) {
        super.init(frame: frame)
        preferredBehavioralStyle = .pad
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }
}
