import MailCore
import UIKit

/// What a swipe action's button wears.
nonisolated public enum SwipeTint: Hashable, Sendable {
    /// Clear glass, the row showing through it, that fills with the theme's color on a full swipe.
    case clear
    /// The system red that actions which delete or report wear as standard.
    case red
    /// A color picked with the system color picker.
    case custom(RGBColor)

    /// How the tint is stored: `clear`, `red`, or a picked color's hex string, such as `#3366FF`.
    var rawValue: String {
        switch self {
        case .clear: "clear"
        case .red: "red"
        case .custom(let color): color.hex
        }
    }

    /// `nil` for anything this build doesn't know.
    init?(rawValue: String) {
        switch rawValue {
        case "clear": self = .clear
        case "red": self = .red
        default:
            guard let color = RGBColor(hex: rawValue) else { return nil }
            self = .custom(color)
        }
    }

    /// The color as picked, before it's shaded for light or dark mode; `nil` for clear glass.
    var picked: UIColor? {
        switch self {
        case .clear: nil
        case .red: .systemRed
        case .custom(let color): UIColor(color)
        }
    }

    /// What the button wears from the moment it shows: the picked color shaded to suit light or dark mode, under a
    /// symbol that stands out from it. `nil` for clear glass, which is never shaded.
    var shade: (fill: UIColor, symbol: UIColor)? {
        picked.map { ($0.shadedFill, $0.shadedSymbol) }
    }
}

extension SwipeChoice {
    /// Red for the actions that delete or report a thread, clear glass for the rest.
    nonisolated var standardTint: SwipeTint {
        switch self {
        case .trash, .spam: .red
        case .read, .star, .archive, .snooze: .clear
        }
    }
}

/// The tint of each swipe action. One the reader never changed wears its standard tint.
nonisolated public struct SwipeTints: Equatable, Sendable {
    /// Only the tints that differ from their action's standard one.
    private var changed: [SwipeChoice: SwipeTint]

    public static let standard = SwipeTints(changed: [:])

    private init(changed: [SwipeChoice: SwipeTint]) {
        self.changed = changed.filter { $0.value != $0.key.standardTint }
    }

    public subscript(choice: SwipeChoice) -> SwipeTint {
        get { changed[choice] ?? choice.standardTint }
        set { changed[choice] = newValue == choice.standardTint ? nil : newValue }
    }

    /// The changed tints by action, as stored. An action or tint this build doesn't know, as from a newer one, is
    /// skipped.
    init(stored: [String: String]) {
        self.init(
            changed: Dictionary(
                uniqueKeysWithValues: stored.compactMap { choice, tint in
                    SwipeChoice(rawValue: choice).flatMap { choice in SwipeTint(rawValue: tint).map { (choice, $0) } }
                }))
    }

    var stored: [String: String] {
        Dictionary(uniqueKeysWithValues: changed.map { ($0.key.rawValue, $0.value.rawValue) })
    }
}
