/// What each of a viewer's arrangements shows for a state, as plain values the scene coordinator builds its screens
/// from: a narrow window's one stack, or a wide window's columns. A message window shows `reading` alone.
extension WindowState {
    /// One screen of a narrow window's stack.
    public enum ScreenEntry: Hashable, Sendable {
        case mailboxes
        case list(List)
        case reader(Reading)
    }

    /// What a wide window shows beside its sidebar of mailboxes.
    public struct Columns: Hashable, Sendable {
        /// What the column beside the list shows.
        public enum Detail: Hashable, Sendable {
            case reader(Reading)
            /// Nothing read: the pane says so.
            case nothing
        }

        public var list: List
        public var detail: Detail

        public init(list: List, detail: Detail) {
            self.list = list
            self.detail = detail
        }
    }

    /// A narrow window's stack, bottom to top: the mailboxes, then the list unless the window is back at them, then
    /// the conversation read over it.
    public var stack: [ScreenEntry] {
        switch depth {
        case .mailboxes: [.mailboxes]
        case .list: [.mailboxes, .list(list)] + (reading.map { [.reader($0)] } ?? [])
        }
    }

    /// A wide window's list, and what reads beside it. A window back at the mailboxes when narrow shows its list.
    public var columns: Columns {
        Columns(list: list, detail: reading.map(Columns.Detail.reader) ?? .nothing)
    }
}
