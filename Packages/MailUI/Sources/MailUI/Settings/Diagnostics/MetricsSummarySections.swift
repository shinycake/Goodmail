import FieldDiagnostics
import SwiftUI

/// A day's figures, in the order a developer looks for trouble: crashes and other exits, hangs, launch times, memory
/// and disk.
struct MetricsSummarySections: View {
    let summary: MetricsSummary

    var body: some View {
        Section {
            if otherExits.isEmpty { none }
            ForEach(otherExits, id: \.reason) { ExitRow(tally: $0) }
        } header: {
            Text(
                "Crashes and Exits", tableName: "Diagnostics", bundle: .module,
                comment: "Section: the times the system ended the app, crashes included")
        } footer: {
            Text(
                "Each time the system ended Goodmail, other than when you closed it.", tableName: "Diagnostics",
                bundle: .module, comment: "Explains the crashes and exits section")
        }

        Section {
            if summary.hangs.count == 0 {
                none
            } else {
                LabeledContent {
                    Text(summary.hangs.count, format: .number)
                } label: {
                    Text(
                        "Hangs", tableName: "Diagnostics", bundle: .module,
                        comment: "Hangs: a section of a day's report, and its row that counts them")
                }
                ForEach(summary.hangs.buckets, id: \.start) { bucket in
                    LabeledContent {
                        Text(bucket.count, format: .number)
                    } label: {
                        Text(
                            "\(DiagnosticReportView.duration(bucket.start)) to \(DiagnosticReportView.duration(bucket.end))",
                            tableName: "Diagnostics", bundle: .module,
                            comment: "Row: the hangs that lasted between the two times")
                    }
                }
            }
        } header: {
            Text(
                "Hangs", tableName: "Diagnostics", bundle: .module,
                comment: "Hangs: a section of a day's report, and its row that counts them")
        }

        Section {
            if summary.launches.count == 0, summary.resumes.count == 0 { none }
            percentiles(
                of: summary.launches,
                typical: Text(
                    "Typical Launch", tableName: "Diagnostics", bundle: .module, comment: "Row: the median launch time"),
                slowest: Text(
                    "Slowest Launches", tableName: "Diagnostics", bundle: .module,
                    comment: "Row: the time the slowest tenth of launches took longer than"))
            percentiles(
                of: summary.resumes,
                typical: Text(
                    "Typical Resume", tableName: "Diagnostics", bundle: .module,
                    comment: "Row: the median time to come back from the background"),
                slowest: Text(
                    "Slowest Resumes", tableName: "Diagnostics", bundle: .module,
                    comment: "Row: the time the slowest tenth of returns from the background took longer than"))
        } header: {
            Text("Launch", tableName: "Diagnostics", bundle: .module, comment: "Section: how long the app took to open")
        } footer: {
            Text(
                "From the tap to the first frame. Half took less than the typical time, and 1 in 10 took longer than the slowest.",
                tableName: "Diagnostics", bundle: .module, comment: "Explains the launch and resume times")
        }

        Section {
            if summary.peakMemory == nil, memoryExits.isEmpty { none }
            if let peak = summary.peakMemory {
                LabeledContent {
                    Text(DiagnosticReportView.size(peak))
                } label: {
                    Text(
                        "Peak Memory", tableName: "Diagnostics", bundle: .module,
                        comment: "Row: the most memory the app took in a day")
                }
            }
            ForEach(memoryExits, id: \.reason) { ExitRow(tally: $0) }
        } header: {
            Text("Memory", tableName: "Diagnostics", bundle: .module, comment: "Section: the memory the app took")
        }

        Section {
            if let writes = summary.diskWrites {
                LabeledContent {
                    Text(DiagnosticReportView.size(writes))
                } label: {
                    Text(
                        "Written to Disk", tableName: "Diagnostics", bundle: .module,
                        comment: "Row: what the app wrote to disk")
                }
            } else {
                none
            }
        } header: {
            Text("Disk", tableName: "Diagnostics", bundle: .module, comment: "Section: what the app wrote to disk")
        }
    }

    /// Exits for want of memory, which show with the memory the app took.
    private var memoryExits: [ExitTally] { summary.exits.filter(\.reason.isMemory) }
    private var otherExits: [ExitTally] { summary.exits.filter { !$0.reason.isMemory } }

    private var none: some View {
        Text(
            "None", tableName: "Diagnostics", bundle: .module,
            comment: "Shown in a section the day's report has nothing for"
        )
        .foregroundStyle(.secondary)
    }

    /// The median and the 90th percentile, when anything was measured.
    @ViewBuilder
    private func percentiles(of histogram: DurationHistogram, typical: Text, slowest: Text) -> some View {
        if let median = histogram.percentile(0.5), let slow = histogram.percentile(0.9) {
            LabeledContent {
                Text(DiagnosticReportView.duration(median))
            } label: {
                typical
            }
            LabeledContent {
                Text(DiagnosticReportView.duration(slow))
            } label: {
                slowest
            }
        }
    }
}

/// How many times the system ended the app for one reason, on screen and off.
private struct ExitRow: View {
    let tally: ExitTally

    var body: some View {
        LabeledContent {
            Text(tally.total, format: .number)
        } label: {
            Text(tally.reason.title)
            Text(
                "\(tally.foreground) on screen, \(tally.background) in the background", tableName: "Diagnostics",
                bundle: .module,
                comment:
                    "Under an exit reason: how many times the app was ended while open, and while in the background")
        }
    }
}

extension ExitReason {
    fileprivate var isMemory: Bool {
        switch self {
        case .memoryLimit, .memoryPressure: true
        case .cpuLimit, .watchdog, .lockedFile, .taskTimeout, .badAccess, .illegalInstruction, .abnormal: false
        }
    }

    fileprivate var title: String {
        switch self {
        case .memoryLimit:
            String(
                localized: "Memory Limit", table: "Diagnostics", bundle: .module,
                comment:
                    "The system ending the app for using too much memory: a report's title, and a reason for an exit")
        case .memoryPressure:
            String(
                localized: "Memory Needed Elsewhere", table: "Diagnostics", bundle: .module,
                comment: "Exit reason: the system took the memory back while the app was in the background")
        case .cpuLimit:
            String(
                localized: "CPU Limit", table: "Diagnostics", bundle: .module,
                comment: "Exit reason: the app used too much processor time in the background")
        case .watchdog:
            String(
                localized: "Watchdog", table: "Diagnostics", bundle: .module,
                comment: "Exit reason: the app took too long to launch, resume or answer")
        case .lockedFile:
            String(
                localized: "Suspended With a Locked File", table: "Diagnostics", bundle: .module,
                comment: "Exit reason: the app was suspended holding a lock on a shared file")
        case .taskTimeout:
            String(
                localized: "Background Task Ran Out of Time", table: "Diagnostics", bundle: .module,
                comment: "Exit reason: a background task took too long")
        case .badAccess:
            String(
                localized: "Bad Memory Access", table: "Diagnostics", bundle: .module,
                comment: "Exit reason: a crash touching memory the app may not")
        case .illegalInstruction:
            String(
                localized: "Illegal Instruction", table: "Diagnostics", bundle: .module,
                comment: "Exit reason: a crash on an instruction the app may not run, such as a failed check")
        case .abnormal:
            String(
                localized: "Other Crash", table: "Diagnostics", bundle: .module,
                comment: "Exit reason: the app crashed or ended itself in another way")
        }
    }
}
