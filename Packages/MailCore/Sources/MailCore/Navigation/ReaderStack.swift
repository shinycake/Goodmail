/// How a narrow window's one stack takes a reader: over the list, or in the place of the reader on show, so the stack
/// is never list › reader › reader and Back always goes to the list (R1).
public enum ReaderStack: Equatable, Sendable {
    /// No reader is on show: the new one goes on top, as a push.
    case push
    /// A reader is on show: the new one takes its place, keeping the first `keeping` screens under it. Whatever was
    /// over the old reader goes with it.
    case replace(keeping: Int)

    /// For a stack whose screens, bottom to top, are readers where `readers` says.
    public init(readers: [Bool]) {
        self = readers.firstIndex(of: true).map { .replace(keeping: $0) } ?? .push
    }
}
