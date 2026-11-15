import Foundation
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
}
