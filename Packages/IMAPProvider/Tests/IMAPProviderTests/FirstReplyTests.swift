import Foundation
import Synchronization
import Testing

@testable import IMAPProvider

/// CFNetwork can call a stream task's read handler twice, and a checked continuation resumed twice traps: the
/// build 9 crash. `firstReply` keeps the first answer and drops the rest.
struct FirstReplyTests {
    struct Failure: Error, Equatable {}

    @Test func aSecondReplyIsIgnored() async throws {
        let value = try await firstReply { reply in
            reply(.success(1))
            reply(.success(2))
        }
        #expect(value == 1)
    }

    @Test func dataAfterAFailureIsIgnored() async throws {
        await #expect(throws: Failure()) {
            try await firstReply { (reply: @escaping @Sendable (Result<Int, any Error>) -> Void) in
                reply(.failure(Failure()))
                reply(.success(2))
            }
        }
    }

    @Test func repliesRacingOnOtherThreadsResumeOnce() async throws {
        let value = try await firstReply { (reply: @escaping @Sendable (Result<Int, any Error>) -> Void) in
            DispatchQueue.concurrentPerform(iterations: 8) { reply(.success($0)) }
        }
        #expect((0..<8).contains(value))
    }

    /// A stream task's read never hears of cancellation, so an IDLE watch cancelled as the app left the foreground
    /// kept its connection until the read timed out.
    @Test func cancellingTheCallerAnswersAReplyThatNeverComes() async throws {
        let started = AsyncStream.makeStream(of: Void.self)
        let read = Task {
            try await firstReply { (_: @escaping @Sendable (Result<Int, any Error>) -> Void) in
                started.continuation.yield()
            }
        }
        for await _ in started.stream { break }
        read.cancel()
        await #expect(throws: CancellationError.self) { try await read.value }
    }

    @Test func aCallerCancelledBeforehandDoesntStart() async throws {
        let starts = Mutex(0)
        await #expect(throws: CancellationError.self) {
            // A task added to a cancelled group starts cancelled.
            try await withThrowingTaskGroup(of: Int.self) { group in
                group.cancelAll()
                group.addTask {
                    try await firstReply { (reply: @escaping @Sendable (Result<Int, any Error>) -> Void) in
                        starts.withLock { $0 += 1 }
                        reply(.success(1))
                    }
                }
                return try await group.next()
            }
        }
        #expect(starts.withLock { $0 } == 0)
    }

    @Test func aReplyAfterTheCancellationIsDropped() async throws {
        let late = Mutex<(@Sendable (Result<Int, any Error>) -> Void)?>(nil)
        let started = AsyncStream.makeStream(of: Void.self)
        let read = Task {
            try await firstReply { reply in
                late.withLock { $0 = reply }
                started.continuation.yield()
            }
        }
        for await _ in started.stream { break }
        read.cancel()
        await #expect(throws: CancellationError.self) { try await read.value }
        late.withLock { $0 }?(.success(1))
    }
}
