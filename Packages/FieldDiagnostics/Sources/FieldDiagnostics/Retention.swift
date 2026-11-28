public import Foundation

/// How much the archive keeps: reports up to an age, and the newest of them up to a size.
public struct Retention: Sendable {
    /// What the archive keeps on the device: three months, in 20 MB at most.
    public static let standard = Retention(maxAge: 90 * 86_400, maxBytes: 20_000_000)

    public let maxAge: TimeInterval
    public let maxBytes: Int

    public init(maxAge: TimeInterval, maxBytes: Int) {
        self.maxAge = maxAge
        self.maxBytes = maxBytes
    }

    /// A kept report: when its period ended, and the bytes its files take.
    public struct Entry: Sendable {
        public let id: String
        public let date: Date
        public let bytes: Int

        public init(id: String, date: Date, bytes: Int) {
            self.id = id
            self.date = date
            self.bytes = bytes
        }
    }

    /// The reports to remove at `now`: those older than the age, and, newest first, each that no longer fits in the
    /// size beside the ones kept before it.
    public func expired(_ entries: [Entry], now: Date) -> Set<String> {
        var kept = 0
        var expired = Set<String>()
        for entry in entries.sorted(by: { $0.date > $1.date }) {
            if now.timeIntervalSince(entry.date) > maxAge || kept + entry.bytes > maxBytes {
                expired.insert(entry.id)
            } else {
                kept += entry.bytes
            }
        }
        return expired
    }
}
