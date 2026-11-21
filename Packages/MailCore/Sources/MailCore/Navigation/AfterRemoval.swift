/// What a window shows after the reader archives, deletes, moves, snoozes or mutes the conversation they're reading
/// (R7).
public enum AfterRemoval: String, CaseIterable, Sendable {
    /// The conversation below it in the list, else the one above.
    case next
    /// The list, with nothing open.
    case list
}
