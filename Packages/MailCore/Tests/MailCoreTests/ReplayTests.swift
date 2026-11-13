import Testing

@testable import MailCore

struct ReplayTests {
    @Test func throttlingIsRetriedForEveryRequest() {
        #expect(Replay.safe.allowsRetry(after: .throttled))
        #expect(Replay.onlyIfRefused.allowsRetry(after: .throttled))
    }

    @Test func aServerErrorIsRetriedOnlyWhereSendingTwiceDoesNoHarm() {
        #expect(Replay.safe.allowsRetry(after: .serverError))
        #expect(!Replay.onlyIfRefused.allowsRetry(after: .serverError))
    }

    @Test func anyOtherFailureIsNeverRetried() {
        #expect(!Replay.safe.allowsRetry(after: nil))
        #expect(!Replay.onlyIfRefused.allowsRetry(after: nil))
    }
}
