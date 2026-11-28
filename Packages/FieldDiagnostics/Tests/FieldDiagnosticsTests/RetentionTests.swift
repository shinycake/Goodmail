import FieldDiagnostics
import Foundation
import Testing

/// The archive keeps the newest reports, up to an age and a size.
struct RetentionTests {
    private static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private static let day: TimeInterval = 86_400

    private static func entry(_ id: String, daysAgo: Double, bytes: Int = 1_000) -> Retention.Entry {
        Retention.Entry(id: id, date: now.addingTimeInterval(-daysAgo * day), bytes: bytes)
    }

    @Test func theStandardKeepsNinetyDaysAndTwentyMegabytes() {
        #expect(Retention.standard.maxAge == 90 * Self.day)
        #expect(Retention.standard.maxBytes == 20_000_000)
    }

    @Test func reportsOlderThanTheAgeExpire() {
        let retention = Retention(maxAge: 30 * Self.day, maxBytes: .max)
        let entries = [Self.entry("new", daysAgo: 1), Self.entry("edge", daysAgo: 30), Self.entry("old", daysAgo: 31)]
        #expect(retention.expired(entries, now: Self.now) == ["old"])
    }

    /// Past the size, the oldest go first, until what is left fits.
    @Test func theOldestExpireOnceTheArchiveIsFull() {
        let retention = Retention(maxAge: .infinity, maxBytes: 2_500)
        let entries = [
            Self.entry("b", daysAgo: 2), Self.entry("a", daysAgo: 1), Self.entry("c", daysAgo: 3),
            Self.entry("d", daysAgo: 4),
        ]
        #expect(retention.expired(entries, now: Self.now) == ["c", "d"])
    }

    /// One report too big for the size on its own goes alone: the older ones still fit.
    @Test func aReportTooBigOnItsOwnLeavesTheOthers() {
        let retention = Retention(maxAge: .infinity, maxBytes: 2_500)
        let entries = [
            Self.entry("huge", daysAgo: 1, bytes: 3_000), Self.entry("b", daysAgo: 2), Self.entry("c", daysAgo: 3),
        ]
        #expect(retention.expired(entries, now: Self.now) == ["huge"])
    }

    @Test func nothingExpiresWithinBoth() {
        let entries = [Self.entry("a", daysAgo: 1), Self.entry("b", daysAgo: 89)]
        #expect(Retention.standard.expired(entries, now: Self.now).isEmpty)
    }
}
