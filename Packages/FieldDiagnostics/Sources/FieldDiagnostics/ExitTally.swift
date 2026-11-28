/// Why the system ended the app, as MetricKit counts its exits. The ordinary ones, as when the reader closes the app,
/// aren't kept.
public enum ExitReason: String, Sendable, Codable, CaseIterable {
    /// It used more memory than the system allows it.
    case memoryLimit
    /// The system needed the memory back while it was in the background.
    case memoryPressure
    /// It used too much CPU in the background.
    case cpuLimit
    /// It took too long to launch, resume or answer, and the watchdog ended it.
    case watchdog
    /// It was suspended holding a lock on a file another process shares, such as the mail database.
    case lockedFile
    /// A background task it began ran out of time.
    case taskTimeout
    /// It touched memory it may not: a crash.
    case badAccess
    /// It ran an instruction it may not: a crash, such as a failed precondition.
    case illegalInstruction
    /// It ended itself or crashed in another way.
    case abnormal
}

/// How many times the app was ended for one reason over a period, on screen and off.
public struct ExitTally: Sendable, Codable, Hashable {
    public let reason: ExitReason
    public let foreground: Int
    public let background: Int

    public init(reason: ExitReason, foreground: Int, background: Int) {
        self.reason = reason
        self.foreground = foreground
        self.background = background
    }

    public var total: Int { foreground + background }

    /// One tally for each reason that happened, in the order of `ExitReason`.
    public static func tallies(foreground: [ExitReason: Int], background: [ExitReason: Int]) -> [ExitTally] {
        ExitReason.allCases.compactMap { reason in
            let tally = ExitTally(
                reason: reason, foreground: foreground[reason] ?? 0, background: background[reason] ?? 0)
            return tally.total > 0 ? tally : nil
        }
    }
}
