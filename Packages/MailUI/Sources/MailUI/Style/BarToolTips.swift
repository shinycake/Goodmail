import UIKit

/// Names a navigation bar's buttons, with their keys, when the pointer rests on one, as a Mac toolbar's buttons do. A
/// bar button item has no tooltip of its own, so the bar answers for the items registered with `set`.
final class BarToolTips: NSObject, UIToolTipInteractionDelegate {
    private static let tips = NSMapTable<UIBarButtonItem, NSString>.weakToStrongObjects()

    static func set(_ item: UIBarButtonItem, _ tip: String) {
        tips.setObject(tip as NSString, forKey: item)
    }

    /// The bars already answering, so each gets one interaction.
    private let bars = NSHashTable<UINavigationBar>.weakObjects()

    func install(on bar: UINavigationBar) {
        guard !bars.contains(bar) else { return }
        bars.add(bar)
        let interaction = UIToolTipInteraction()
        interaction.delegate = self
        bar.addInteraction(interaction)
    }

    func toolTipInteraction(
        _ interaction: UIToolTipInteraction, configurationAt point: CGPoint
    ) -> UIToolTipConfiguration? {
        guard let bar = interaction.view as? UINavigationBar, let item = bar.topItem else { return nil }
        let items = (item.leadingItemGroups + item.trailingItemGroups).flatMap(\.barButtonItems)
        for shown in items {
            guard let tip = Self.tips.object(forKey: shown), let frame = shown.frame(in: bar), frame.contains(point)
            else { continue }
            return UIToolTipConfiguration(toolTip: tip as String, in: frame)
        }
        return nil
    }
}
