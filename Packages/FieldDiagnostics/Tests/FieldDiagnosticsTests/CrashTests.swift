import FieldDiagnostics
import Testing

/// A crash reads by the names a developer looks for, not the numbers MetricKit sends.
struct CrashTests {
    @Test(arguments: [
        (1, "EXC_BAD_ACCESS"), (2, "EXC_BAD_INSTRUCTION"), (6, "EXC_BREAKPOINT"), (10, "EXC_CRASH"),
        (11, "EXC_RESOURCE"), (12, "EXC_GUARD"),
    ])
    func machExceptionsHaveTheirNames(type: Int, name: String) {
        #expect(Crash(exceptionType: type, signal: nil, reason: nil).exceptionName == name)
    }

    @Test(arguments: [(4, "SIGILL"), (5, "SIGTRAP"), (6, "SIGABRT"), (9, "SIGKILL"), (10, "SIGBUS"), (11, "SIGSEGV")])
    func signalsHaveTheirNames(signal: Int, name: String) {
        #expect(Crash(exceptionType: nil, signal: signal, reason: nil).signalName == name)
    }

    @Test func anUnknownNumberReadsAsTheNumber() {
        let crash = Crash(exceptionType: 99, signal: 77, reason: nil)
        #expect(crash.exceptionName == "99")
        #expect(crash.signalName == "77")
        #expect(Crash(exceptionType: nil, signal: nil, reason: nil).exceptionName == nil)
    }
}
