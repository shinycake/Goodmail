import Foundation
import Synchronization

@testable import MailWristHost

/// Takes what a host gives back, as the watch app keeps it, for a test to read in order; or turns it down, as a
/// watch whose mailbox couldn't be stored does.
final class GivenBack: Sendable {
    private let stream: AsyncStream<WristOwnHost.Handback>
    private let continuation: AsyncStream<WristOwnHost.Handback>.Continuation
    private let state = Mutex(State())

    private struct State {
        var refusing = false
        var offers = 0
    }

    struct Refused: Error {}

    init() {
        (stream, continuation) = AsyncStream.makeStream()
    }

    /// The host's `handBack`.
    var receiver: WristOwnHost.Receiver {
        { [continuation, self] handbacks in
            let refusing = self.state.withLock { state in
                state.offers += 1
                return state.refusing
            }
            if refusing { throw Refused() }
            for handback in handbacks { continuation.yield(handback) }
        }
    }

    /// Turns down what is given back from now on, or takes it again with `false`.
    func refuse(_ refusing: Bool) {
        state.withLock { $0.refusing = refusing }
    }

    /// How many times the host has given something back, taken or not.
    var offers: Int { state.withLock(\.offers) }

    /// The next thing taken.
    func next() async -> WristOwnHost.Handback? {
        for await handback in stream { return handback }
        return nil
    }
}
