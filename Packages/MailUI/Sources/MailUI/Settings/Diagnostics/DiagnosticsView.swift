import FieldDiagnostics
import SwiftUI

/// The Settings row that opens Diagnostics.
struct DiagnosticsSection: View {
    let model: DiagnosticsModel

    var body: some View {
        Section {
            NavigationLink {
                DiagnosticsView(model: model)
            } label: {
                Text(DiagnosticsView.title)
            }
        }
    }
}

/// The reports the system sent about how Goodmail ran on this device, by day: its daily figures, and each crash,
/// hang and exception. Each can be shared with a developer, and all of them deleted.
struct DiagnosticsView: View {
    let model: DiagnosticsModel
    @State private var confirmingDelete = false

    static var title: String {
        String(
            localized: "Diagnostics", table: "Diagnostics", bundle: .module,
            comment: "Title of the page of reports the system sent about how the app ran")
    }

    var body: some View {
        content
            .navigationTitle(Self.title)
            .toolbar {
                if !model.files.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        ShareLink(items: model.files) {
                            Label {
                                Text(
                                    "Share All", tableName: "Diagnostics", bundle: .module,
                                    comment: "Shares every diagnostic report's file")
                            } icon: {
                                Image(systemName: "square.and.arrow.up")
                            }
                        }
                    }
                }
            }
            .task { await model.load() }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .loading, .deleting:
            ProgressView()
        case .failed(let failure):
            ContentUnavailableView {
                Label {
                    Text(Self.title(of: failure))
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                }
            }
        case .loaded(let days) where days.isEmpty:
            ContentUnavailableView {
                Label {
                    Text(
                        "No Reports Yet", tableName: "Diagnostics", bundle: .module,
                        comment: "Shown when the system hasn't sent any diagnostic report")
                } icon: {
                    Image(systemName: "stethoscope")
                }
            } description: {
                Text(
                    "The system sends a report about once a day, and one after a crash or a hang the next time Goodmail opens.",
                    tableName: "Diagnostics", bundle: .module, comment: "Explains when diagnostic reports arrive")
            }
        case .loaded(let days):
            List {
                ForEach(days) { day in
                    Section {
                        ForEach(day.reports) { report in
                            NavigationLink {
                                DiagnosticReportView(report: report, file: model.file(for: report))
                            } label: {
                                DiagnosticRow(report: report)
                            }
                        }
                    } header: {
                        Text(day.start, format: .dateTime.weekday(.wide).day().month(.wide))
                    }
                }
                Section {
                    Button(role: .destructive) {
                        confirmingDelete = true
                    } label: {
                        Text(
                            "Delete All Reports", tableName: "Diagnostics", bundle: .module,
                            comment: "Deletes every diagnostic report from the device")
                    }
                    .confirmationDialog(
                        Text(
                            "Delete All Reports?", tableName: "Diagnostics", bundle: .module,
                            comment: "Title asking to confirm deleting every diagnostic report"),
                        isPresented: $confirmingDelete, titleVisibility: .visible
                    ) {
                        Button(role: .destructive) {
                            model.deleteAll()
                        } label: {
                            Text(
                                "Delete All", tableName: "Diagnostics", bundle: .module,
                                comment: "Confirms deleting every diagnostic report")
                        }
                    } message: {
                        Text(
                            "Reports you shared aren't affected.", tableName: "Diagnostics", bundle: .module,
                            comment: "Says that deleting the reports leaves copies already shared")
                    }
                } footer: {
                    Text(
                        "Reports come from the system and stay on this device unless you share them.",
                        tableName: "Diagnostics", bundle: .module, comment: "Explains where diagnostic reports go")
                }
            }
        }
    }

    private static func title(of failure: DiagnosticsModel.Failure) -> String {
        switch failure {
        case .reading:
            String(
                localized: "Couldn’t Read the Reports", table: "Diagnostics", bundle: .module,
                comment: "Shown when the diagnostic reports on the device can't be read")
        case .deleting:
            String(
                localized: "Couldn’t Delete the Reports", table: "Diagnostics", bundle: .module,
                comment: "Shown when the diagnostic reports couldn't be deleted")
        }
    }
}

/// One report in the list: what it is, a figure that tells it apart, and when it came.
private struct DiagnosticRow: View {
    let report: DiagnosticReport

    var body: some View {
        LabeledContent {
            // A day's metrics cover the whole day, so only an event has a time of its own.
            if case .event = report.content {
                Text(report.period.end, format: .dateTime.hour().minute())
            }
        } label: {
            Label {
                VStack(alignment: .leading) {
                    Text(report.content.title)
                    if let detail = report.content.detail {
                        Text(detail).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            } icon: {
                Image(systemName: report.content.symbol)
            }
        }
    }
}
