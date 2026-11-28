#if DEBUG
    import FieldDiagnostics
    import Foundation
    import OSLog

    /// Launch with `-GoodmailSeedDiagnostics <folder>` to replace the diagnostic reports with the deliveries in the
    /// folder's JSON files, as `Packages/FieldDiagnostics/Tests/FieldDiagnosticsTests/Fixtures` holds, so Settings >
    /// Diagnostics can be seen and tested on a simulator, which MetricKit sends nothing to. They are moved in time so
    /// the newest ends now and the others keep their distance from it, so the retention keeps them.
    nonisolated enum TestDiagnostics {
        @concurrent static func seedIfRequested(into archive: DiagnosticsArchive) async {
            guard let folder = UserDefaults.standard.string(forKey: "GoodmailSeedDiagnostics") else { return }
            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let deliveries = try FileManager.default.contentsOfDirectory(
                    at: URL(filePath: folder, directoryHint: .isDirectory), includingPropertiesForKeys: nil
                )
                .filter { $0.pathExtension == "json" }
                .map { try decoder.decode(Delivery.self, from: Data(contentsOf: $0)) }
                let newest = deliveries.map(\.period.end).max() ?? .now
                let shift = Date.now.timeIntervalSince(newest)
                try await archive.deleteAll()
                for delivery in deliveries {
                    try await archive.store(
                        Delivery(
                            period: DateInterval(
                                start: delivery.period.start.addingTimeInterval(shift),
                                duration: delivery.period.duration),
                            appVersion: delivery.appVersion, content: delivery.content, raw: delivery.raw))
                }
            } catch {
                Logger(subsystem: "com.idanbirman.goodmail", category: "diagnostics")
                    .error("Seeding diagnostics failed: \(error, privacy: .public)")
            }
        }
    }
#endif
