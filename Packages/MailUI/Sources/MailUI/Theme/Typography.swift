import UIKit

/// The app's type: the system font (SF Pro, and the system Hebrew face for Hebrew) in semantic text styles, so every
/// font follows Dynamic Type, accessibility sizes and Bold Text like the rest of iOS.
public enum Typography {
    public static var title: UIFont { system(.title2, weight: .semibold) }
    public static var subject: UIFont { system(.body, weight: .semibold) }
    public static var body: UIFont { system(.body) }

    /// The system font in `style` at `weight`, scaled to the user's text size.
    public static func system(_ style: UIFont.TextStyle, weight: UIFont.Weight = .regular) -> UIFont {
        // Start from the default size so UIFontMetrics can scale it to the user's setting.
        let defaultSize = UITraitCollection(preferredContentSizeCategory: .large)
        let descriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: style, compatibleWith: defaultSize)
            .addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: weight]])
        return UIFontMetrics(forTextStyle: style).scaledFont(for: UIFont(descriptor: descriptor, size: 0))
    }
}
