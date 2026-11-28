import Synchronization
import Testing

@testable import MailCore

/// A log given a sink hands it each record: the level, the fixed sentence, and the error's type and description,
/// nothing more.
struct MailLogTests {
    struct Refused: Error, CustomStringConvertible {
        var description: String { "550 dana@example.com: no such user" }
    }

    @Test(arguments: [MailLog.Level.error, .fault])
    func aSinkGetsEachRecord(at level: MailLog.Level) {
        let entries = Entries()
        let log = MailLog(category: "outgoing") { entry in entries.append(entry) }
        switch level {
        case .error: log.error("A write failed", Refused())
        case .fault: log.fault("A write failed", Refused())
        }
        #expect(
            entries.all == [
                MailLog.Entry(
                    category: "outgoing", level: level, message: "A write failed",
                    errorType: "MailCoreTests.MailLogTests.Refused", error: "550 dana@example.com: no such user")
            ]
        )
    }
}

private final class Entries: Sendable {
    private let entries = Mutex<[MailLog.Entry]>([])

    func append(_ entry: MailLog.Entry) { entries.withLock { $0.append(entry) } }
    var all: [MailLog.Entry] { entries.withLock { $0 } }
}
