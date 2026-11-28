import FieldDiagnostics
import Foundation

extension DiagnosticsArchive {
    /// The app's reports from MetricKit, in its own container: the extensions and the watch keep none (ADR-042). One
    /// archive for the feed that fills it and every Settings page that shows it, so its actor orders their work.
    nonisolated static let app = DiagnosticsArchive(
        directory: .applicationSupportDirectory.appending(path: "Diagnostics", directoryHint: .isDirectory))
}
