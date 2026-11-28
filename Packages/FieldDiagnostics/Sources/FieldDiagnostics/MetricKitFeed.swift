#if canImport(MetricKit)
    import Foundation
    import MetricKit
    import OSLog

    /// Keeps each report MetricKit sends in the archive, from when it's made until it goes. MetricKit sends a day's
    /// metrics about once a day, and a crash or hang's diagnostic the next time the app runs after it.
    ///
    /// iOS 27's `MetricManager` hands its reports over as async sequences of `Sendable` values, so nothing here runs
    /// on MetricKit's own queue: one task the feed owns reads both sequences, off the main actor, and stores each
    /// report in turn through the archive actor.
    public final class MetricKitFeed: Sendable {
        private let reading: Task<Void, Never>

        public init(archive: DiagnosticsArchive) {
            let manager = MetricManager()
            reading = Task {
                await withDiscardingTaskGroup { group in
                    group.addTask {
                        for await report in manager.metricReports {
                            await Self.keep(in: archive) { try Delivery(report) }
                        }
                    }
                    group.addTask {
                        for await report in manager.diagnosticReports {
                            await Self.keep(in: archive) { try Delivery(report) }
                        }
                    }
                }
            }
        }

        deinit { reading.cancel() }

        private static let log = Logger(subsystem: "com.idanbirman.goodmail", category: "diagnostics")

        /// Stores the report `delivery` reads; one it can't read or keep is only logged, as the payload is MetricKit's
        /// to send again or not.
        private static func keep(in archive: DiagnosticsArchive, _ delivery: () throws -> Delivery?) async {
            do {
                guard let delivery = try delivery() else {
                    log.notice("Skipped a MetricKit diagnostic of a kind this version doesn't read")
                    return
                }
                try await archive.store(delivery)
            } catch {
                log.error("Couldn't keep a MetricKit report: \(error, privacy: .private)")
            }
        }
    }
#endif
