import Foundation

extension Preferences {
    /// The quick actions a desktop window's rows show under the pointer. Never set, they read as the standard ones.
    /// Turning them off keeps the picks, so turning them back on brings the same ones.
    public static var hoverActions: HoverActions {
        get { defaults.object(forKey: showsHoverActionsKey) as? Bool ?? true ? .on(hoverActionPicks) : .off }
        set {
            switch newValue {
            case .off: defaults.set(false, forKey: showsHoverActionsKey)
            case .on(let picks):
                defaults.set(true, forKey: showsHoverActionsKey)
                defaults.set(picks.choices.map(\.rawValue), forKey: hoverActionsKey)
            }
        }
    }

    /// The picks last chosen, whether or not hover actions are on. An action this build doesn't know is skipped.
    public static var hoverActionPicks: HoverActions.Picks {
        guard let stored = defaults.stringArray(forKey: hoverActionsKey) else { return .standard }
        return HoverActions.Picks(stored.compactMap(SwipeChoice.init(rawValue:)))
    }

    nonisolated static let showsHoverActionsKey = "showsHoverActions"
    nonisolated static let hoverActionsKey = "hoverActions"
}
