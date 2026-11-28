public import Foundation

/// A report MetricKit sent, as the archive keeps it: a day's metrics, or one thing that went wrong.
public struct DiagnosticReport: Sendable, Codable, Hashable, Identifiable {
    /// What a report says.
    public enum Content: Sendable, Codable, Hashable {
        /// The day's figures.
        case metrics(MetricsSummary)
        /// One crash, hang or exception.
        case event(DiagnosticEvent)
    }

    /// The period's start and a hash of the payload, so the same payload handed over again has the same one.
    public let id: String
    /// The day the metrics cover, or when the event happened.
    public let period: DateInterval
    /// The version of the app that ran, as "1.0 (42)", when MetricKit says.
    public let appVersion: String?
    public let content: Content

    public init(id: String, period: DateInterval, appVersion: String?, content: Content) {
        self.id = id
        self.period = period
        self.appVersion = appVersion
        self.content = content
    }
}

/// A report as MetricKit hands it over: what it says, and the payload it came in, which the reader can share.
public struct Delivery: Sendable, Codable, Hashable {
    public let period: DateInterval
    public let appVersion: String?
    public let content: DiagnosticReport.Content
    /// MetricKit's report, encoded as JSON.
    public let raw: Data

    public init(period: DateInterval, appVersion: String?, content: DiagnosticReport.Content, raw: Data) {
        self.period = period
        self.appVersion = appVersion
        self.content = content
        self.raw = raw
    }
}
