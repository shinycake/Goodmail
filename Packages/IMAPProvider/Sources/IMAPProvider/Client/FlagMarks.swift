/// The flags that give a message its labels: read (`\Seen`) and starred (`\Flagged`). A server without CONDSTORE
/// can't say which messages' flags changed, so the cursor keeps these for each folder's latest messages and the
/// next sync compares.
struct FlagMarks: OptionSet, Codable, Hashable, Sendable {
    let rawValue: UInt8

    static let seen = FlagMarks(rawValue: 1)
    static let flagged = FlagMarks(rawValue: 2)

    init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    init(_ flags: Set<String>) {
        self = []
        if flags.contains(#"\Seen"#) { insert(.seen) }
        if flags.contains(#"\Flagged"#) { insert(.flagged) }
    }

    /// How many of a folder's latest messages a sync compares. Older ones change rarely, and a full resync still
    /// catches them.
    static let window = 200

    /// The UIDs in both whose marks differ. A UID only in one was added or removed, which the sync reads otherwise.
    static func changed(from old: [UInt32: FlagMarks], to new: [UInt32: FlagMarks]) -> [UInt32] {
        new.compactMap { uid, marks in
            guard let before = old[uid], before != marks else { return nil }
            return uid
        }.sorted()
    }
}
