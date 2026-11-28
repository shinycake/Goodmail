import FieldDiagnostics
import Foundation
import Testing

/// The archive keeps each report MetricKit hands over once, as the report and the payload it came in, and lists them
/// newest first.
struct DiagnosticsArchiveTests {
    private static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private static let day: TimeInterval = 86_400

    /// A folder of its own for each test, removed after it.
    private final class Folder {
        let url = FileManager.default.temporaryDirectory.appending(
            path: "DiagnosticsArchiveTests-\(UUID().uuidString)", directoryHint: .isDirectory)

        func archive(retention: Retention = .standard) -> DiagnosticsArchive {
            DiagnosticsArchive(directory: url, retention: retention, now: { DiagnosticsArchiveTests.now })
        }

        var files: [String] {
            ((try? FileManager.default.contentsOfDirectory(atPath: url.path(percentEncoded: false))) ?? []).sorted()
        }

        deinit { try? FileManager.default.removeItem(at: url) }
    }

    private static func hang(daysAgo: Double, seconds: Double = 1.5, raw: String? = nil) -> Delivery {
        let end = now.addingTimeInterval(-daysAgo * day)
        return Delivery(
            period: DateInterval(start: end.addingTimeInterval(-60), end: end), appVersion: "1.0 (42)",
            content: .event(.hang(duration: seconds)),
            raw: Data((raw ?? "{\"hang\":\(seconds),\"at\":\(daysAgo)}").utf8))
    }

    @Test func anEmptyArchiveHasNoReports() async throws {
        let folder = Folder()
        #expect(try await folder.archive().reports().isEmpty)
        withExtendedLifetime(folder) {}
    }

    @Test func aStoredDeliveryComesBackAsItsReportWithItsPayload() async throws {
        let folder = Folder()
        let archive = folder.archive()
        let delivery = Self.hang(daysAgo: 1)
        let stored = try await archive.store(delivery)
        #expect(stored.period == delivery.period)
        #expect(stored.appVersion == "1.0 (42)")
        #expect(stored.content == .event(.hang(duration: 1.5)))
        #expect(try await archive.reports() == [stored])
        #expect(try Data(contentsOf: archive.rawFile(for: stored.id)) == delivery.raw)
    }

    @Test func reportsComeNewestFirst() async throws {
        let folder = Folder()
        let archive = folder.archive()
        for daysAgo in [3.0, 1, 2] { try await archive.store(Self.hang(daysAgo: daysAgo)) }
        let ends = try await archive.reports().map(\.period.end)
        #expect(ends == [1.0, 2, 3].map { Self.now.addingTimeInterval(-$0 * Self.day) })
    }

    /// MetricKit can hand the same report over again, as on the next launch: it is kept once.
    @Test func storingTheSameDeliveryAgainKeepsOneCopy() async throws {
        let folder = Folder()
        let archive = folder.archive()
        let first = try await archive.store(Self.hang(daysAgo: 1))
        let again = try await archive.store(Self.hang(daysAgo: 1))
        #expect(first.id == again.id)
        #expect(try await archive.reports().count == 1)
        #expect(folder.files.count == 2, "one report and one payload")
    }

    @Test func deliveriesOfTheSamePeriodWithOtherContentAreKeptApart() async throws {
        let folder = Folder()
        let archive = folder.archive()
        try await archive.store(Self.hang(daysAgo: 1, raw: "{\"first\":true}"))
        try await archive.store(Self.hang(daysAgo: 1, raw: "{\"second\":true}"))
        #expect(try await archive.reports().count == 2)
    }

    /// A report this version can't read, as one a newer version wrote, is left out of the list but kept, payload
    /// and all, for a version that can.
    @Test func anUnreadableReportIsSkippedAndKept() async throws {
        let folder = Folder()
        let archive = folder.archive()
        let newer = try await archive.store(Self.hang(daysAgo: 2))
        let kept = try await archive.store(Self.hang(daysAgo: 1))
        try Data("{\"id\":\"\(newer.id)\",\"schema\":2}".utf8).write(
            to: folder.url.appending(path: "\(newer.id).report.json"))
        #expect(try await archive.reports() == [kept])
        #expect(folder.files.count == 4)
    }

    /// A file of no report, as a payload whose report was never written or one an interrupted write left, goes.
    @Test func filesOfNoReportAreRemoved() async throws {
        let folder = Folder()
        let archive = folder.archive()
        let kept = try await archive.store(Self.hang(daysAgo: 1))
        try Data("{}".utf8).write(to: folder.url.appending(path: "123-abc.payload.json"))
        try Data("partial".utf8).write(to: folder.url.appending(path: ".payload.json.tmp-1234"))
        #expect(try await archive.reports() == [kept])
        #expect(folder.files == ["\(kept.id).payload.json", "\(kept.id).report.json"].sorted())
    }

    /// Past the size, the archive drops the oldest reports' files, measured as they are on disk.
    @Test func storingKeepsTheArchiveWithinItsSize() async throws {
        let folder = Folder()
        try await folder.archive().store(Self.hang(daysAgo: 9, raw: String(repeating: "x", count: 1_000)))
        let bytes = folder.files.reduce(0) { total, name in
            total + ((try? folder.url.appending(path: name).resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        try await folder.archive().deleteAll()
        #expect(bytes > 1_000, "one report's files, measured")

        let archive = folder.archive(retention: Retention(maxAge: .infinity, maxBytes: bytes * 2 + bytes / 2))
        for daysAgo in [4, 3, 2, 1] {
            let raw = String(repeating: "\(daysAgo)", count: 1_000)
            try await archive.store(Self.hang(daysAgo: Double(daysAgo), raw: raw))
        }
        let ends = try await archive.reports().map(\.period.end)
        #expect(ends == [1.0, 2].map { Self.now.addingTimeInterval(-$0 * Self.day) })
        #expect(folder.files.count == 4)
    }

    /// MetricKit handing a report over again mends the copy kept, if it can't be read.
    @Test func storingAgainMendsADamagedCopy() async throws {
        let folder = Folder()
        let archive = folder.archive()
        let stored = try await archive.store(Self.hang(daysAgo: 1))
        try Data("{\"id\":".utf8).write(to: folder.url.appending(path: "\(stored.id).report.json"))
        try await archive.store(Self.hang(daysAgo: 1))
        #expect(try await archive.reports() == [stored])
    }

    /// The retention holds when the list is read too, so a report past it doesn't show while nothing new arrives.
    @Test func listingAppliesTheRetention() async throws {
        let folder = Folder()
        let early = DiagnosticsArchive(directory: folder.url, now: { Self.now.addingTimeInterval(-100 * Self.day) })
        try await early.store(Self.hang(daysAgo: 95))
        #expect(try await early.reports().count == 1, "within the retention when it was stored")
        #expect(try await folder.archive().reports().isEmpty)
        #expect(folder.files.isEmpty)
    }

    @Test func storingAppliesTheRetention() async throws {
        let folder = Folder()
        let archive = folder.archive(retention: Retention(maxAge: 10 * Self.day, maxBytes: .max))
        try await archive.store(Self.hang(daysAgo: 11))
        let kept = try await archive.store(Self.hang(daysAgo: 2))
        #expect(try await archive.reports() == [kept])
        #expect(folder.files.count == 2)
    }

    @Test func deleteAllRemovesEveryReport() async throws {
        let folder = Folder()
        let archive = folder.archive()
        try await archive.store(Self.hang(daysAgo: 1))
        try await archive.store(Self.hang(daysAgo: 2))
        try await archive.deleteAll()
        #expect(try await archive.reports().isEmpty)
        try await archive.deleteAll()  // and again, with nothing there
        let after = try await archive.store(Self.hang(daysAgo: 1))
        #expect(try await archive.reports() == [after], "the archive keeps working after")
    }

    @Test func aDailySummaryIsKeptWithItsFigures() async throws {
        let folder = Folder()
        let archive = folder.archive()
        let summary = MetricsSummary(
            launches: DurationHistogram([.init(start: 0, end: 0.5, count: 4)]),
            resumes: DurationHistogram([]), hangs: DurationHistogram([.init(start: 0.25, end: 0.5, count: 2)]),
            peakMemory: 180_000_000, diskWrites: 52_000_000,
            exits: [ExitTally(reason: .memoryLimit, foreground: 0, background: 1)])
        let delivery = Delivery(
            period: DateInterval(start: Self.now.addingTimeInterval(-Self.day), end: Self.now), appVersion: nil,
            content: .metrics(summary), raw: Data("{}".utf8))
        try await archive.store(delivery)
        #expect(try await archive.reports().map(\.content) == [.metrics(summary)])
    }
}
