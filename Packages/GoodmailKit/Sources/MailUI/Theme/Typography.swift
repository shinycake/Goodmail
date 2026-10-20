import UIKit

/// New York carries the content (titles, subjects, message bodies); everything else stays in SF Pro.
/// Every font scales with Dynamic Type.
public enum Typography {
    public static var title: UIFont { serif(.title2, weight: .semibold) }
    public static var subject: UIFont { serif(.body, weight: .semibold) }
    public static var body: UIFont { serif(.body) }

    public static func serif(_ style: UIFont.TextStyle, weight: UIFont.Weight = .regular) -> UIFont {
        // Start from the default size so UIFontMetrics can scale it to the user's setting.
        let defaultSize = UITraitCollection(preferredContentSizeCategory: .large)
        let descriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: style, compatibleWith: defaultSize)
        let serif = (descriptor.withDesign(.serif) ?? descriptor)
            .addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: weight]])
        return UIFontMetrics(forTextStyle: style).scaledFont(for: UIFont(descriptor: serif, size: 0))
    }
}
