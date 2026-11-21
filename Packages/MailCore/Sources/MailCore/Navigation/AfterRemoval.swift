/// What a window shows after the reader archives, deletes, moves, snoozes or mutes the conversation they're reading
/// (R7). The reader chooses in Settings, and the choice follows them to their other devices.
public enum AfterRemoval: String, CaseIterable, Sendable {
    /// The conversation below it in the list, else the one above.
    case next
    /// The list, with nothing open.
    case list

    /// As iOS Mail does unless told otherwise.
    public static let standard = AfterRemoval.next

    /// The choice stored as `value`. Nothing stored, or a value from a later build, reads as the standard one.
    public init(stored value: String?) {
        self = value.flatMap(Self.init(rawValue:)) ?? .standard
    }
}
