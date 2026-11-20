public import UIKit

/// How the reader drives a window. Decided once per window, at the app's edge, and handed down as a trait
/// (`UITraitCollection.interactionStyle`). It answers how the window is driven, never how big it is: layout comes from
/// size classes and widths. Screens read it and never ask which device they are on.
public enum InteractionStyle: Sendable, Equatable {
    /// Fingers first: bars at the bottom, sheets, a Select mode, swipes. Every iPhone and iPad, including an iPad with
    /// a keyboard attached.
    case touch
    /// A pointer and a keyboard first: a window toolbar, windows for compose and settings, selection without a mode.
    /// Mac windows.
    case desktop

    /// The style of a window whose scene reports `idiom`. Only the Mac idiom drives a window by pointer and keyboard.
    public init(idiom: UIUserInterfaceIdiom) {
        self = idiom == .mac ? .desktop : .touch
    }

    /// Whether the app shows a menu bar for `idiom`: on iPad, and always on the Mac. This is about the device, not
    /// the window, so it is not an `InteractionStyle`: an iPad is `.touch` and still has a menu bar.
    public static func showsMenuBar(idiom: UIUserInterfaceIdiom) -> Bool {
        idiom == .pad || InteractionStyle(idiom: idiom) == .desktop
    }
}

/// Where a window's views find its `InteractionStyle`. The app sets it on each window; views without it are touch.
nonisolated struct InteractionStyleTrait: UITraitDefinition {
    static let defaultValue = InteractionStyle.touch
}

extension UIMutableTraits {
    public var interactionStyle: InteractionStyle {
        get { self[InteractionStyleTrait.self] }
        set { self[InteractionStyleTrait.self] = newValue }
    }
}

extension UITraitCollection {
    public var interactionStyle: InteractionStyle { self[InteractionStyleTrait.self] }
}
