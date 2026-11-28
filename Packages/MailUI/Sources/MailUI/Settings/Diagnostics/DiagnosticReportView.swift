import FieldDiagnostics
import Foundation
import SwiftUI

/// One report's figures, with its file to share with a developer.
struct DiagnosticReportView: View {
    let report: DiagnosticReport
    /// The payload the report came in, as the system sent it.
    let file: URL

    var body: some View {
        Form {
            switch report.content {
            case .metrics(let summary): MetricsSummarySections(summary: summary)
            case .event(let event): EventSection(event: event)
            }
            Section {
                LabeledContent {
                    Text((report.period.start..<report.period.end).formatted(.interval.month().day().hour().minute()))
                } label: {
                    Text("Time", tableName: "Diagnostics", bundle: .module, comment: "Row: the period a report covers")
                }
                if let version = report.appVersion {
                    LabeledContent {
                        Text(verbatim: "\u{2066}\(version)\u{2069}")
                    } label: {
                        Text(
                            "Version", tableName: "Diagnostics", bundle: .module,
                            comment: "Row: the version of the app a report is about")
                    }
                }
            }
        }
        .navigationTitle(report.content.title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ShareLink(item: file) {
                    Label {
                        Text(
                            "Share Report", tableName: "Diagnostics", bundle: .module,
                            comment: "Shares one diagnostic report's file")
                    } icon: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
    }

    /// A time in milliseconds under a second, or seconds. Isolated left to right, so a right-to-left label keeps the
    /// number before its unit.
    static func duration(_ seconds: TimeInterval) -> String {
        let milliseconds = (seconds * 1_000).rounded()
        let measurement =
            milliseconds < 1_000
            ? Measurement(value: milliseconds, unit: UnitDuration.milliseconds)
            : Measurement(value: seconds, unit: UnitDuration.seconds)
        let text = measurement.formatted(
            .measurement(
                width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0...1))))
        return "\u{2066}\(text)\u{2069}"
    }

    /// In decimal units, as the system's storage screens count, isolated left to right as `duration` is.
    static func size(_ bytes: Int64) -> String {
        "\u{2066}" + bytes.formatted(.byteCount(style: .file, spellsOutZero: false)) + "\u{2069}"
    }
}

/// The figures of one crash, hang or exception.
private struct EventSection: View {
    let event: DiagnosticEvent

    var body: some View {
        Section {
            switch event {
            case .crash(let crash):
                if let exception = crash.exceptionName {
                    figure(
                        Text(verbatim: exception),
                        Text(
                            "Exception", tableName: "Diagnostics", bundle: .module,
                            comment: "Row: the Mach exception a crash raised"))
                }
                if let signal = crash.signalName {
                    figure(
                        Text(verbatim: signal),
                        Text(
                            "Signal", tableName: "Diagnostics", bundle: .module,
                            comment: "Row: the signal that ended the app"))
                }
                if let reason = crash.reason {
                    Text(verbatim: reason).font(.callout.monospaced()).textSelection(.enabled)
                }
            case .hang(let duration), .slowLaunch(let duration):
                figure(
                    Text(DiagnosticReportView.duration(duration)),
                    Text(
                        "Duration", tableName: "Diagnostics", bundle: .module,
                        comment: "Row: how long a hang or a launch took"))
            case .cpuException(let cpuTime, let sampledTime):
                figure(
                    Text(DiagnosticReportView.duration(cpuTime)),
                    Text(
                        "CPU Time", tableName: "Diagnostics", bundle: .module,
                        comment: "Row: the processor time the app used"))
                figure(
                    Text(DiagnosticReportView.duration(sampledTime)),
                    Text(
                        "Measured Over", tableName: "Diagnostics", bundle: .module,
                        comment: "Row: the time over which the app used the processor time above"))
            case .diskWrite(let bytes):
                figure(
                    Text(DiagnosticReportView.size(bytes)),
                    Text(
                        "Written to Disk", tableName: "Diagnostics", bundle: .module,
                        comment: "Row: what the app wrote to disk"))
            case .memoryException:
                Text(
                    "The system ended Goodmail for using more memory than it allows.", tableName: "Diagnostics",
                    bundle: .module, comment: "Explains a memory limit report")
            }
        }
    }

    private func figure(_ value: Text, _ label: Text) -> some View {
        LabeledContent {
            value
        } label: {
            label
        }
    }
}

extension DiagnosticReport.Content {
    /// What the report is, for its row and its page.
    var title: String {
        switch self {
        case .metrics:
            String(
                localized: "Daily Summary", table: "Diagnostics", bundle: .module,
                comment: "A report of a day's launch times, hangs, memory, disk writes and exits")
        case .event(.crash):
            String(localized: "Crash", table: "Diagnostics", bundle: .module, comment: "A crash report")
        case .event(.hang):
            String(
                localized: "Hang", table: "Diagnostics", bundle: .module,
                comment: "A report of the app not answering for a while")
        case .event(.cpuException):
            String(
                localized: "High CPU Use", table: "Diagnostics", bundle: .module,
                comment: "A report of the app using too much processor time")
        case .event(.diskWrite):
            String(
                localized: "Heavy Disk Writes", table: "Diagnostics", bundle: .module,
                comment: "A report of the app writing too much to disk in a day")
        case .event(.slowLaunch):
            String(
                localized: "Slow Launch", table: "Diagnostics", bundle: .module, comment: "A report of a slow launch")
        case .event(.memoryException):
            String(
                localized: "Memory Limit", table: "Diagnostics", bundle: .module,
                comment:
                    "The system ending the app for using too much memory: a report's title, and a reason for an exit")
        }
    }

    /// The figure that tells one report from another of its kind.
    var detail: String? {
        switch self {
        case .metrics, .event(.memoryException): nil
        case .event(.crash(let crash)): crash.exceptionName ?? crash.signalName
        case .event(.hang(let duration)), .event(.slowLaunch(let duration)): DiagnosticReportView.duration(duration)
        case .event(.cpuException(let cpuTime, _)): DiagnosticReportView.duration(cpuTime)
        case .event(.diskWrite(let bytes)): DiagnosticReportView.size(bytes)
        }
    }

    var symbol: String {
        switch self {
        case .metrics: "chart.bar"
        case .event(.crash): "exclamationmark.octagon"
        case .event(.hang): "hourglass"
        case .event(.cpuException): "cpu"
        case .event(.diskWrite): "internaldrive"
        case .event(.slowLaunch): "tortoise"
        case .event(.memoryException): "memorychip"
        }
    }
}
