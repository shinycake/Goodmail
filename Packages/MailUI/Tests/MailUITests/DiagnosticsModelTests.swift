import FieldDiagnostics
import Foundation
import Testing

@testable import MailUI

/// Settings > Diagnostics: it reads the archive's reports into days, newest first, and deletes them on request.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct DiagnosticsModelTests {
    nonisolated private static let now = Date(timeIntervalSinceReferenceDate: 800_054_000)
    private static let hour: TimeInterval = 3_600

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }()

    /// A folder of its own for each test, removed after it.
    private final class Folder {
        let url = FileManager.default.temporaryDirectory.appending(
            path: "DiagnosticsModelTests-\(UUID().uuidString)", directoryHint: .isDirectory)

        var archive: DiagnosticsArchive {
            DiagnosticsArchive(directory: url, now: { DiagnosticsModelTests.now })
        }

        deinit { try? FileManager.default.removeItem(at: url) }
    }

    private static func hang(hoursAgo: Double) -> Delivery {
        let end = now.addingTimeInterval(-hoursAgo * hour)
        return Delivery(
            period: DateInterval(start: end.addingTimeInterval(-30), end: end), appVersion: "1.0 (1)",
            content: .event(.hang(duration: 1)), raw: Data("{\"at\":\(hoursAgo)}".utf8))
    }

    @Test func itLoadsTheReportsByDayNewestFirst() async throws {
        let folder = Folder()
        let archive = folder.archive
        // `now` is 2026-05-09 at 21:13 UTC: two hangs that day, and one the day before.
        let late = try await archive.store(Self.hang(hoursAgo: 1))
        let early = try await archive.store(Self.hang(hoursAgo: 20))
        let earlier = try await archive.store(Self.hang(hoursAgo: 30))
        let model = DiagnosticsModel(archive: archive, calendar: Self.calendar)
        #expect(model.phase == .loading)

        await model.load()
        let today = Self.calendar.startOfDay(for: Self.now)
        let yesterday = try #require(Self.calendar.date(byAdding: .day, value: -1, to: today))
        #expect(
            model.phase
                == .loaded([
                    DiagnosticsModel.Day(start: today, reports: [late, early]),
                    DiagnosticsModel.Day(start: yesterday, reports: [earlier]),
                ]))
        #expect(model.files == [late, early, earlier].map { archive.rawFile(for: $0.id) })
    }

    /// A day's metrics run midnight to midnight, so they end on the next day: they list under the day they cover,
    /// after that next day's events.
    @Test func aDaysMetricsListUnderTheDayTheyCover() async throws {
        let folder = Folder()
        let archive = folder.archive
        let today = Self.calendar.startOfDay(for: Self.now)
        let yesterday = try #require(Self.calendar.date(byAdding: .day, value: -1, to: today))
        let summary = MetricsSummary(
            launches: DurationHistogram([]), resumes: DurationHistogram([]), hangs: DurationHistogram([]),
            peakMemory: nil, diskWrites: nil, exits: [])
        let metrics = try await archive.store(
            Delivery(
                period: DateInterval(start: yesterday, end: today), appVersion: nil, content: .metrics(summary),
                raw: Data("{}".utf8)))
        let hang = try await archive.store(Self.hang(hoursAgo: 20))
        let model = DiagnosticsModel(archive: archive, calendar: Self.calendar)
        await model.load()
        #expect(
            model.phase
                == .loaded([
                    DiagnosticsModel.Day(start: today, reports: [hang]),
                    DiagnosticsModel.Day(start: yesterday, reports: [metrics]),
                ]))
    }

    @Test func anEmptyArchiveLoadsAsNoDays() async {
        let folder = Folder()
        let model = DiagnosticsModel(archive: folder.archive, calendar: Self.calendar)
        await model.load()
        #expect(model.phase == .loaded([]))
        withExtendedLifetime(folder) {}
        #expect(model.files.isEmpty)
    }

    /// An archive whose folder can't be listed, here because a file stands where it goes, fails to load.
    @Test func anArchiveThatCantBeReadSaysSo() async throws {
        let folder = Folder()
        try Data("not a folder".utf8).write(to: folder.url)
        let model = DiagnosticsModel(archive: folder.archive, calendar: Self.calendar)
        await model.load()
        #expect(model.phase == .failed(.reading))
        withExtendedLifetime(folder) {}
    }

    @Test func deleteAllEmptiesTheArchiveAndThePage() async throws {
        let folder = Folder()
        let archive = folder.archive
        try await archive.store(Self.hang(hoursAgo: 1))
        let model = DiagnosticsModel(archive: archive, calendar: Self.calendar)
        await model.load()

        model.deleteAll()
        #expect(model.phase.isDeleting)
        model.deleteAll()  // a second tap while it goes does nothing more
        await model.load()  // nor does the page coming back meanwhile
        await model.settled()
        #expect(model.phase == .loaded([]))
        #expect(try await archive.reports().isEmpty)
    }
}

extension DiagnosticsModel.Phase {
    fileprivate var isDeleting: Bool {
        if case .deleting = self { true } else { false }
    }
}
