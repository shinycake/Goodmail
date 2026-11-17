/// How long a toast with Undo stays up. Five seconds is time enough to read it and tap Undo, but VoiceOver and Switch
/// Control move from element to element and need longer to reach the button, so the toast waits for them.
nonisolated enum ToastTime {
    /// The least time a toast stays while VoiceOver or Switch Control runs.
    static let assisted: Duration = .seconds(20)

    /// `standard`, or at least `assisted` when `assistiveTechnologyRuns`.
    static func lasting(_ standard: Duration, assistiveTechnologyRuns: Bool) -> Duration {
        assistiveTechnologyRuns ? max(standard, assisted) : standard
    }
}
