public import Foundation

/// One thing that went wrong, as MetricKit reports it the next time the app runs.
public enum DiagnosticEvent: Sendable, Codable, Hashable {
    case crash(Crash)
    /// The main thread didn't answer for `duration` seconds.
    case hang(duration: TimeInterval)
    /// The app used `cpuTime` seconds of CPU over `sampledTime` seconds, past what the system allows.
    case cpuException(cpuTime: TimeInterval, sampledTime: TimeInterval)
    /// The app wrote `bytes` to disk in a day, past what the system allows.
    case diskWrite(bytes: Int64)
    /// A launch took `duration` seconds.
    case slowLaunch(duration: TimeInterval)
    /// The system ended the app for using too much memory. Only iPhone and iPad report it.
    case memoryException
}

/// How the app crashed: the Mach exception and the signal, by number, and what the app or the system said about it.
public struct Crash: Sendable, Codable, Hashable {
    public let exceptionType: Int?
    public let signal: Int?
    /// The Objective-C exception's message, or the reason the system gave for ending the app.
    public let reason: String?

    public init(exceptionType: Int?, signal: Int?, reason: String?) {
        self.exceptionType = exceptionType
        self.signal = signal
        self.reason = reason
    }

    /// The exception's name, as `EXC_BAD_ACCESS`, or its number for one this doesn't know.
    public var exceptionName: String? {
        exceptionType.map { Self.exceptionNames[$0] ?? String($0) }
    }

    /// The signal's name, as `SIGSEGV`, or its number for one this doesn't know.
    public var signalName: String? {
        signal.map { Self.signalNames[$0] ?? String($0) }
    }

    /// Darwin's numbers, from `mach/exception_types.h`.
    private static let exceptionNames = [
        1: "EXC_BAD_ACCESS", 2: "EXC_BAD_INSTRUCTION", 3: "EXC_ARITHMETIC", 4: "EXC_EMULATION", 5: "EXC_SOFTWARE",
        6: "EXC_BREAKPOINT", 7: "EXC_SYSCALL", 8: "EXC_MACH_SYSCALL", 9: "EXC_RPC_ALERT", 10: "EXC_CRASH",
        11: "EXC_RESOURCE", 12: "EXC_GUARD", 13: "EXC_CORPSE_NOTIFY",
    ]

    /// Darwin's numbers, from `sys/signal.h`, which differ from Linux's.
    private static let signalNames = [
        1: "SIGHUP", 2: "SIGINT", 3: "SIGQUIT", 4: "SIGILL", 5: "SIGTRAP", 6: "SIGABRT", 7: "SIGEMT", 8: "SIGFPE",
        9: "SIGKILL", 10: "SIGBUS", 11: "SIGSEGV", 12: "SIGSYS", 13: "SIGPIPE", 14: "SIGALRM", 15: "SIGTERM",
    ]
}
