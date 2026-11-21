public import MailCore

extension MailCommand {
    /// What a toolbar button for the command says when the pointer rests on it: its name and its keys, as
    /// "Archive ⌃⌘A", from the same table the menu bar uses.
    public var toolTip: String {
        guard let chord = keys.chord else { return title }
        return "\(title) \(chord)"
    }
}
