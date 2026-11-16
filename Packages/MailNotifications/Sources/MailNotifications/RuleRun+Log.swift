public import MailCore
public import OSLog

extension RuleRun {
    /// Where the app and the notification extension log what running the rules couldn't do.
    public static let log = Logger(subsystem: "com.idanbirman.goodmail", category: "rules")

    /// Logs each action that failed, naming the rule and when it ran, as "a push".
    public func logFailures(after occasion: String) {
        for failure in failures {
            Self.log.error(
                "Rule \(failure.rule, privacy: .private) failed after \(occasion, privacy: .public): \(failure.error, privacy: .public)"
            )
        }
    }
}
