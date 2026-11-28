#if canImport(MetricKit)
    import Foundation
    import MetricKit

    // MetricKit's reports read into the archive's plain values, with the report itself kept as JSON to share. Only
    // the figures the screen shows are read; the rest stay in the JSON.

    extension Delivery {
        /// A day's metrics. The day's own entry holds the figures for all of it; the others break it down.
        init(_ report: MetricReport) throws {
            let values = report.intervalEntries.isEmpty ? [] : report.intervalEntries.fullDayEntry.values
            let version = report.environment.map { "\($0.latestApplicationVersion) (\($0.applicationBuildVersion))" }
            self.init(
                period: report.timeRange, appVersion: version, content: .metrics(MetricsSummary(values)),
                raw: try Self.encoded(report))
        }

        /// One crash, hang or exception; `nil` for a kind this doesn't know.
        init?(_ report: MetricKit.DiagnosticReport) throws {
            guard let event = DiagnosticEvent(report.result) else { return nil }
            let environment = report.environment
            self.init(
                period: report.timeRange,
                appVersion: "\(environment.applicationVersion) (\(environment.applicationBuildVersion))",
                content: .event(event), raw: try Self.encoded(report))
        }

        /// Readable, for the developer the reader shares it with.
        private static func encoded(_ report: some Encodable) throws -> Data {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            return try encoder.encode(report)
        }
    }

    extension MetricsSummary {
        fileprivate init(_ values: [MetricResult]) {
            var launches = DurationHistogram([])
            var resumes = DurationHistogram([])
            var hangs = DurationHistogram([])
            var peakMemory: Int64?
            var diskWrites: Int64?
            var foreground: [ExitReason: Int] = [:]
            var background: [ExitReason: Int] = [:]
            for value in values {
                switch value {
                case .timeToFirstDraw(let metric): launches = DurationHistogram(metric.histogram)
                case .applicationResumeTime(let metric): resumes = DurationHistogram(metric.histogram)
                case .hangTime(let metric): hangs = DurationHistogram(metric.histogram)
                case .logicalDiskWrites(let metric): diskWrites = metric.value.bytes
                case .foregroundTermination(let metric):
                    foreground = [
                        .memoryLimit: metric.memoryLimitTerminationCount, .badAccess: metric.badAccessTerminationCount,
                        .abnormal: metric.abnormalTerminationCount,
                        .illegalInstruction: metric.illegalInstructionTerminationCount,
                        .watchdog: metric.watchdogTerminationCount,
                    ]
                case .backgroundTermination(let metric):
                    background = [
                        .memoryLimit: metric.memoryLimitTerminationCount,
                        .memoryPressure: metric.systemPressureTerminationCount,
                        .cpuLimit: metric.highCPUTerminationCount, .badAccess: metric.badAccessTerminationCount,
                        .abnormal: metric.abnormalTerminationCount,
                        .illegalInstruction: metric.illegalInstructionTerminationCount,
                        .watchdog: metric.watchdogTerminationCount, .lockedFile: metric.fileLockTerminationCount,
                        .taskTimeout: metric.taskTimeoutTerminationCount,
                    ]
                #if !targetEnvironment(macCatalyst)
                    case .peakMemory(let metric): peakMemory = metric.value.bytes
                #endif
                default: break
                }
            }
            self.init(
                launches: launches, resumes: resumes, hangs: hangs, peakMemory: peakMemory, diskWrites: diskWrites,
                exits: ExitTally.tallies(foreground: foreground, background: background))
        }
    }

    extension DiagnosticEvent {
        fileprivate init?(_ result: DiagnosticResult) {
            switch result {
            case .crash(let crash):
                self = .crash(
                    Crash(
                        exceptionType: crash.exceptionType, signal: crash.signal,
                        reason: crash.exceptionReason?.composedMessage ?? crash.terminationReason?.rawValue))
            case .hang(let hang): self = .hang(duration: hang.hangDuration.seconds)
            case .cpuException(let exception):
                self = .cpuException(
                    cpuTime: exception.totalCPUTime.seconds, sampledTime: exception.totalSampledTime.seconds)
            case .diskWriteException(let exception):
                guard let bytes = exception.totalBytesWritten.bytes else { return nil }
                self = .diskWrite(bytes: bytes)
            case .appLaunch(let launch): self = .slowLaunch(duration: launch.launchDuration.seconds)
            #if !targetEnvironment(macCatalyst)
                case .memoryException: self = .memoryException
            #endif
            @unknown default: return nil
            }
        }
    }

    extension DurationHistogram {
        fileprivate init(_ histogram: MetricKit.Histogram<UnitDuration>) {
            self.init(
                histogram.buckets.map {
                    Bucket(start: $0.lowerBound.seconds, end: $0.upperBound.seconds, count: $0.count)
                })
        }
    }

    extension Measurement<UnitDuration> {
        fileprivate var seconds: TimeInterval { converted(to: .seconds).value }
    }

    extension Measurement<UnitInformationStorage> {
        /// `nil` for a value no `Int64` holds, as NaN, which converting would trap on.
        fileprivate var bytes: Int64? { Int64(exactly: converted(to: .bytes).value.rounded()) }
    }
#endif
