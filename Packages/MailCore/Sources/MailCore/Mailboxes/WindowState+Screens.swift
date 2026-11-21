/// What a narrow window's one stack shows for a state, as plain values its screens are kept in step with. A wide
/// window's columns show `list` and `reading` beside its mailboxes, whatever `place` says.
extension WindowState {
    /// One screen of a narrow window's stack.
    public enum ScreenEntry: Hashable, Sendable {
        case mailboxes
        /// The list, `WindowState.list`.
        case list
        case reader(Reading)
    }

    /// A narrow window's stack, bottom to top: the mailboxes, then the list unless the window is back at them, then
    /// the conversation read over it. A message window's is its conversation alone.
    public var stack: [ScreenEntry] {
        switch place {
        case .mailboxes: [.mailboxes]
        case .list(let reading): [.mailboxes, .list] + (reading.map { [.reader($0)] } ?? [])
        case .message(let reading): [.reader(reading)]
        }
    }
}
