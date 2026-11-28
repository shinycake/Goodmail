import Testing

@testable import MailCore

/// Signposts mark intervals around work without changing it: on Apple platforms they go to the system's signpost log,
/// and on Linux they do nothing, so the same calls run there.
struct SignpostTests {
    private struct Failure: Error, Equatable {}

    private static let probe = Signpost("SignpostTests")

    @Test func measureRethrowsTheWorksError() async {
        await #expect(throws: Failure()) {
            try await Self.probe.measure("an account") { throw Failure() }
        }
    }

    /// `#expect` can't call a mutating method, so each `end()` is bound first.
    @Test func aOnceEndsOnlyAfterItBegan() {
        var once = Signpost.Once(Self.probe)
        let endedBeforeBeginning = once.end()
        once.begin()
        let ended = once.end()
        #expect(!endedBeforeBeginning)
        #expect(ended)
    }

    @Test func aOnceEndsOnlyOnce() {
        var once = Signpost.Once(Self.probe)
        once.begin()
        let first = once.end()
        let second = once.end()
        #expect(first)
        #expect(!second)
    }

    @Test func aOnceThatEndedDoesntBeginAgain() {
        var once = Signpost.Once(Self.probe)
        once.begin()
        once.end()
        once.begin()
        let endedAgain = once.end()
        #expect(!endedAgain)
    }
}
