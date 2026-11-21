/// How much of an account's newly arrived mail one run of the rules takes (ADR-033).
public enum RuleCatchUp: Sendable, Equatable {
    /// One batch (`RuleRunner.claimLimit`); the rest waits for the next run. For a process that may be stopped soon:
    /// the notification extension, and the app on iPhone and iPad.
    case oneBatch
    /// Batch after batch until every arrival has been through the rules. A Mac app keeps running, so a flood of mail
    /// all goes through the rules as it comes, instead of 50 conversations every five minutes.
    case everything

    public init(_ policy: PresencePolicy) {
        switch policy {
        case .suspends: self = .oneBatch
        case .keepsRunning: self = .everything
        }
    }
}
