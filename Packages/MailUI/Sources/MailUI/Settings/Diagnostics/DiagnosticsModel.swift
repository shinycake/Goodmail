public import FieldDiagnostics
public import Foundation
public import Observation

/// The Diagnostics page's state: the reports MetricKit sent, by day, newest first, and Delete All.
@Observable
public final class DiagnosticsModel {
    /// The reports of one day, newest first.
    struct Day: Equatable, Identifiable {
        /// The day's first moment, in the reader's calendar.
        let start: Date
        let reports: [DiagnosticReport]

        var id: Date { start }
    }

    /// What the page shows. Only `load()` and `deleteAll()` change it.
    enum Phase: Equatable {
        /// Reading the archive, the first time.
        case loading
        case loaded([Day])
        /// Removing every report, then reading what is left. A load waits for it rather than cutting in.
        case deleting(Task<Void, Never>)
        case failed(Failure)
    }

    enum Failure: Equatable {
        /// The archive couldn't be read.
        case reading
        /// The reports couldn't be removed.
        case deleting
    }

    private(set) var phase = Phase.loading
    @ObservationIgnored private let archive: DiagnosticsArchive
    @ObservationIgnored private let calendar: Calendar

    public init(archive: DiagnosticsArchive, calendar: Calendar = .autoupdatingCurrent) {
        self.archive = archive
        self.calendar = calendar
    }

    /// Reads the reports, unless Delete All is under way: it reads them itself once it's done.
    func load() async {
        if case .deleting = phase { return }
        let read = await read()
        // Delete All began while the archive was read: what it reads after is newer.
        if case .deleting = phase { return }
        phase = read
    }

    /// Removes every report, unless that's already under way, and reads what is left. The removal is the model's
    /// own: it goes on when the page is left.
    func deleteAll() {
        if case .deleting = phase { return }
        phase = .deleting(Task { await self.removeAll() })
    }

    /// Waits for Delete All, if it's under way.
    func settled() async {
        if case .deleting(let task) = phase { await task.value }
    }

    /// The payload a report came in, to share.
    func file(for report: DiagnosticReport) -> URL {
        archive.rawFile(for: report.id)
    }

    /// Every report's payload, newest first, for Share All.
    var files: [URL] {
        guard case .loaded(let days) = phase else { return [] }
        return days.flatMap(\.reports).map(file(for:))
    }

    private func removeAll() async {
        do {
            try await archive.deleteAll()
            phase = await read()
        } catch {
            phase = .failed(.deleting)
        }
    }

    private func read() async -> Phase {
        do {
            return .loaded(days(of: try await archive.reports()))
        } catch {
            return .failed(.reading)
        }
    }

    /// The reports, newest first, by the day the middle of their period falls on: a day's metrics cover midnight to
    /// midnight, so their end is the next day already, and an event's period is a moment.
    private func days(of reports: [DiagnosticReport]) -> [Day] {
        Dictionary(grouping: reports) {
            calendar.startOfDay(for: $0.period.start.addingTimeInterval($0.period.duration / 2))
        }
        .map { Day(start: $0.key, reports: $0.value) }
        .sorted { $0.start > $1.start }
    }
}
