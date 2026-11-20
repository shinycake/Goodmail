/// Keys pressed together for a command, as plain values, so the command table's keys can be checked for clashes on
/// any platform (ADR-034). MailUI turns them into UIKit's inputs and modifier flags.
public struct KeyChord: Hashable, Sendable, CustomStringConvertible {
    public enum Key: Hashable, Sendable {
        /// A character key, written lowercase: Shift is a modifier of its own.
        case character(Character)
        /// Delete, the key left of the backspace on a Mac keyboard, labelled ⌫.
        case delete
        case upArrow
        case downArrow
    }

    public struct Modifiers: OptionSet, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let command = Modifiers(rawValue: 1 << 0)
        public static let shift = Modifiers(rawValue: 1 << 1)
        public static let option = Modifiers(rawValue: 1 << 2)
        public static let control = Modifiers(rawValue: 1 << 3)
    }

    public let modifiers: Modifiers
    public let key: Key

    public init(_ modifiers: Modifiers, _ key: Key) {
        self.modifiers = modifiers
        self.key = key
    }

    public init(_ modifiers: Modifiers, _ character: Character) {
        self.init(modifiers, .character(character))
    }

    /// The chord as a Mac menu writes it, as ⇧⌘N.
    public var description: String {
        let marks: [(Modifiers, String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
        let held = marks.filter { modifiers.contains($0.0) }.map(\.1).joined()
        return switch key {
        case .character(let character): held + character.uppercased()
        case .delete: held + "⌫"
        case .upArrow: held + "↑"
        case .downArrow: held + "↓"
        }
    }

    /// The keys the system's own menus hold in the iPadOS and Mac menu bar: the app menu, Edit, Format, View and
    /// Window, and the File items the system adds itself. A command of the app's own must not repeat one of them.
    public static let heldBySystemMenus: Set<KeyChord> = [
        // The app menu: Hide, Hide Others, Quit.
        KeyChord(.command, "h"), KeyChord([.command, .option], "h"), KeyChord(.command, "q"),
        // File: New Window and Close, where the system offers them, and Print.
        KeyChord([.command, .option], "n"), KeyChord(.command, "w"), KeyChord(.command, "p"),
        // Edit: Undo, Redo, Cut, Copy, Paste, Paste and Match Style, Select All, Emoji and Symbols.
        KeyChord(.command, "z"), KeyChord([.command, .shift], "z"), KeyChord(.command, "x"), KeyChord(.command, "c"),
        KeyChord(.command, "v"), KeyChord([.command, .option, .shift], "v"), KeyChord(.command, "a"),
        KeyChord([.command, .control], " "),
        // Edit > Find: Find, Find and Replace, Find Next, Find Previous, Use Selection for Find.
        KeyChord(.command, "f"), KeyChord([.command, .option], "f"), KeyChord(.command, "g"),
        KeyChord([.command, .shift], "g"), KeyChord(.command, "e"),
        // Edit > Spelling: Show Spelling and Grammar, Check Document Now.
        KeyChord(.command, ":"), KeyChord(.command, ";"),
        // Format > Font: Show Fonts, Bold, Italic, Underline, Bigger, Smaller, Show Colors, Copy Style, Paste Style.
        KeyChord(.command, "t"), KeyChord(.command, "b"), KeyChord(.command, "i"), KeyChord(.command, "u"),
        KeyChord(.command, "+"), KeyChord(.command, "="), KeyChord(.command, "-"), KeyChord([.command, .shift], "c"),
        KeyChord([.command, .option], "c"), KeyChord([.command, .option], "v"),
        // Format > Text: Align Left, Center, Right.
        KeyChord(.command, "{"), KeyChord(.command, "|"), KeyChord(.command, "}"),
        // View: Show Sidebar, Enter Full Screen, Show Toolbar.
        KeyChord([.command, .control], "s"), KeyChord([.command, .control], "f"), KeyChord([.command, .option], "t"),
        // Window: Minimize. Help: the menu search.
        KeyChord(.command, "m"), KeyChord([.command, .shift], "/"),
    ]
}

/// A system menu item whose keys are Apple Mail's for one of the app's commands. Where the menu bar has the item, the
/// command rides on it: the window answers the item's action with the command, or the system does the work itself.
/// Where it hasn't, as on iPhone, the command takes the keys as its own.
public enum SystemMenuItem: CaseIterable, Sendable {
    /// Edit > Find > Find and Replace, which holds Mail's Search Mail keys.
    case findAndReplace
    /// File > Print.
    case print
    /// File > New Window, which opens a window by itself.
    case newWindow
    /// File > Close, which closes the window by itself.
    case close
    /// Edit > Find > Find, which holds ⌘F.
    case find
    /// Edit > Find > Find Next.
    case findNext
    /// Edit > Find > Find Previous.
    case findPrevious
    /// Format > Font > Bigger, which the reader answers by zooming in.
    case biggerText
    /// Format > Font > Smaller.
    case smallerText

    public var keys: KeyChord {
        switch self {
        case .findAndReplace: KeyChord([.command, .option], "f")
        case .print: KeyChord(.command, "p")
        case .newWindow: KeyChord([.command, .option], "n")
        case .close: KeyChord(.command, "w")
        case .find: KeyChord(.command, "f")
        case .findNext: KeyChord(.command, "g")
        case .findPrevious: KeyChord([.command, .shift], "g")
        // ⌘= and not ⌘+, which is typed with Shift and so reaches a key command as another chord; the menu bar's own
        // item answers to both.
        case .biggerText: KeyChord(.command, "=")
        case .smallerText: KeyChord(.command, "-")
        }
    }
}

/// Where a command's keys come from.
public enum CommandKeys: Hashable, Sendable {
    /// None: the command is reached from its menu.
    case none
    /// Keys of the command's own.
    case own(KeyChord)
    /// The keys of a system menu item the command rides on where the menu bar has it.
    case system(SystemMenuItem)

    /// The keys pressed for the command, wherever they come from.
    public var chord: KeyChord? {
        switch self {
        case .none: nil
        case .own(let chord): chord
        case .system(let item): item.keys
        }
    }
}
