/// A sidebar row reached by its number, from ⌘1 to ⌘9 and ⌃⌘1 to ⌃⌘9.
public enum RowShortcut: Equatable, Sendable {
    /// Opens the row's mailbox.
    case goTo(Int)
    /// Moves the picked conversations to the row's mailbox, where it takes them.
    case moveTo(Int)

    /// How many rows have a number.
    public static let count = 9

    /// The row's place in the numbered rows, from 1.
    public var number: Int {
        switch self {
        case .goTo(let number), .moveTo(let number): number
        }
    }

    var chord: KeyChord {
        let digit = Character(String(number))
        return switch self {
        case .goTo: KeyChord(.command, digit)
        case .moveTo: KeyChord([.command, .control], digit)
        }
    }
}

/// The first nine rows a reader could open, in the order the sidebar shows them now, for the number keys. What the
/// sidebar folds away has no number, nor has a row that opens nothing, as a folder that only holds labels.
public struct NumberedRows<Row: Sendable>: Sendable {
    /// The numbered rows; the first is number 1.
    public let rows: [Row]

    /// `visible` is every row on show, headers left out, top to bottom. `isOpenable` says whether the row leads
    /// somewhere.
    public init(visible: [Row], isOpenable: (Row) -> Bool) {
        rows = Array(visible.lazy.filter(isOpenable).prefix(RowShortcut.count))
    }

    /// The row the shortcut names, or `nil` when the sidebar has fewer rows.
    public subscript(shortcut: RowShortcut) -> Row? {
        rows.indices.contains(shortcut.number - 1) ? rows[shortcut.number - 1] : nil
    }
}
