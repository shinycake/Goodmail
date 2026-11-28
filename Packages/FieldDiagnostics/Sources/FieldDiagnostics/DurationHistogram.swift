public import Foundation

/// How long something took, each time it happened over a period, counted in buckets of times: MetricKit's launch,
/// resume and hang histograms.
public struct DurationHistogram: Sendable, Codable, Hashable {
    /// The times from `start` to `end`, in seconds, and how many fell in them.
    public struct Bucket: Sendable, Codable, Hashable {
        public let start: TimeInterval
        public let end: TimeInterval
        public let count: Int

        public init(start: TimeInterval, end: TimeInterval, count: Int) {
            self.start = start
            self.end = end
            self.count = count
        }
    }

    /// The buckets anything fell in, fastest first.
    public let buckets: [Bucket]

    public init(_ buckets: [Bucket]) {
        self.buckets = buckets.filter { $0.count > 0 }.sorted { $0.start < $1.start }
    }

    /// Through `init(_:)`, so a decoded histogram holds to the same order.
    public init(from decoder: any Decoder) throws {
        self.init(try decoder.container(keyedBy: CodingKeys.self).decode([Bucket].self, forKey: .buckets))
    }

    /// How many times it happened.
    public var count: Int { buckets.reduce(0) { $0 + $1.count } }

    /// The time `fraction` of the times were at or under, from 0 to 1: 0.5 is the median. The times within a bucket
    /// are taken to spread evenly across it. `nil` when nothing happened.
    public func percentile(_ fraction: Double) -> TimeInterval? {
        let rank = min(max(fraction, 0), 1) * Double(count)
        var below = 0
        for bucket in buckets {
            if Double(below + bucket.count) >= rank {
                let share = (rank - Double(below)) / Double(bucket.count)
                return bucket.start + (bucket.end - bucket.start) * share
            }
            below += bucket.count
        }
        return buckets.last?.end
    }
}
