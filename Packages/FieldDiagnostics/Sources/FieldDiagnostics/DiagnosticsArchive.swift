public import Foundation

/// The reports MetricKit sent, kept on the device as two files each in one folder: `<id>.report.json`, what the
/// screen shows, and `<id>.payload.json`, MetricKit's own report, which the reader can share. The report is written
/// last, so a report on disk always has its payload. Files are readable once the device is first unlocked after a
/// restart, as the mail database is, so a report that arrives in the background can be kept. The folder is left
/// out of device backups: the reports are this device's, and leave it only when the reader shares one.
///
/// An actor, so a store, a listing and Delete All each see the folder whole; its file work runs off the main actor.
public actor DiagnosticsArchive {
    public nonisolated let directory: URL
    private let retention: Retention
    private let now: @Sendable () -> Date

    public init(directory: URL, retention: Retention = .standard, now: @escaping @Sendable () -> Date = { .now }) {
        self.directory = directory
        self.retention = retention
        self.now = now
    }

    /// Keeps a delivery and returns its report. One already kept, as MetricKit handing a report over again, lands
    /// on the same files, written afresh in case the copy there can't be read. Then the reports past the retention
    /// go, as do files of no report; that is housekeeping, so if it fails the report is still kept, and the next
    /// store or listing tries again. A delivery already past the retention, as one older than it keeps, goes at once.
    @discardableResult
    public func store(_ delivery: Delivery) throws -> DiagnosticReport {
        let report = DiagnosticReport(
            id: Self.id(of: delivery), period: delivery.period, appVersion: delivery.appVersion,
            content: delivery.content)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var folder = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try folder.setResourceValues(values)
        try delivery.raw.write(to: rawFile(for: report.id), options: Self.writing)
        try JSONEncoder().encode(report).write(to: file(report.id, .report), options: Self.writing)
        if let kept = try? kept() { sweep(kept) }
        return report
    }

    /// Every report within the retention, newest first. Those past it go first, so the page never shows one older
    /// than the archive keeps, even when MetricKit has sent nothing for a while. One this version can't read is left
    /// out and kept.
    public func reports() throws -> [DiagnosticReport] {
        sweep(try kept()).compactMap(\.report).sorted { ($0.period.end, $0.id) > ($1.period.end, $1.id) }
    }

    /// The payload a report came in, as MetricKit encoded it.
    public nonisolated func rawFile(for id: DiagnosticReport.ID) -> URL {
        file(id, .payload)
    }

    /// Removes every report.
    public func deleteAll() throws {
        guard FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)) else { return }
        try FileManager.default.removeItem(at: directory)
    }

    // MARK: - Files

    private enum Kind: String {
        case report, payload
    }

    private nonisolated func file(_ id: DiagnosticReport.ID, _ kind: Kind) -> URL {
        directory.appending(path: "\(id).\(kind.rawValue).json", directoryHint: .notDirectory)
    }

    /// The files the folder holds under one id, the bytes they take, and what its report file says.
    private struct Kept {
        let id: DiagnosticReport.ID
        let files: [URL]
        let contents: Contents
        let bytes: Int

        enum Contents {
            case report(DiagnosticReport)
            /// No report file, as a payload whose report was never written or a file an interrupted write left: it
            /// will never show. Files are written whole (`.atomic`), so this is the only way one is broken.
            case orphan
            /// The report file can't be read or decoded: just now, as before the device's first unlock, or by this
            /// version, as one a newer version wrote. Its files stay, payload and all, for the version that can.
            case unreadable
        }

        var report: DiagnosticReport? {
            if case .report(let report) = contents { report } else { nil }
        }
    }

    private func kept() throws -> [Kept] {
        guard FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)) else { return [] }
        let files = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.fileSizeKey])
        let byID = Dictionary(grouping: files) { String($0.lastPathComponent.prefix { $0 != "." }) }
        return byID.map { id, files in
            let bytes = files.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
            return Kept(id: id, files: files, contents: contents(of: file(id, .report)), bytes: bytes)
        }
    }

    private func contents(of reportFile: URL) -> Kept.Contents {
        guard FileManager.default.fileExists(atPath: reportFile.path(percentEncoded: false)) else { return .orphan }
        guard let data = try? Data(contentsOf: reportFile),
            let report = try? JSONDecoder().decode(DiagnosticReport.self, from: data)
        else { return .unreadable }
        return .report(report)
    }

    /// Removes the files of the reports past the retention, and the orphans, and returns the rest. A file
    /// that won't go stays for the next sweep.
    @discardableResult
    private func sweep(_ kept: [Kept]) -> [Kept] {
        let readable = kept.compactMap { kept in
            kept.report.map { Retention.Entry(id: kept.id, date: $0.period.end, bytes: kept.bytes) }
        }
        let expired = retention.expired(readable, now: now())
        return kept.filter { kept in
            switch kept.contents {
            case .report where !expired.contains(kept.id), .unreadable: return true
            case .report, .orphan:
                for url in kept.files { try? FileManager.default.removeItem(at: url) }
                return false
            }
        }
    }

    // MARK: - Encoding

    private static let writing: Data.WritingOptions = [.atomic, .completeFileProtectionUntilFirstUserAuthentication]

    /// The period's start, in seconds since 1970, and the payload's 64-bit FNV-1a hash, so a payload handed over
    /// again lands on its own files.
    private static func id(of delivery: Delivery) -> DiagnosticReport.ID {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in delivery.raw {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        let hex = String(hash, radix: 16)
        return
            "\(Int(delivery.period.start.timeIntervalSince1970))-\(String(repeating: "0", count: 16 - hex.count))\(hex)"
    }
}
