import Foundation
import Synchronization

extension SharedItems {
    /// One read of an item provider, under way: what it found once it is done, and how to stop it. The provider calls
    /// `deliver` once, on a queue of its own; `piece()` is awaited once.
    nonisolated final class PieceRead: Sendable {
        private let state = Mutex(State.reading(nil, waiting: nil))

        private enum State {
            /// Still reading, with its progress once the provider gave it, and whoever awaits the piece.
            case reading(Progress?, waiting: CheckedContinuation<Piece?, Never>?)
            case done(Piece?)
        }

        /// The provider's progress for this read, which cancelling stops.
        func started(_ progress: Progress) {
            state.withLock { state in
                guard case .reading(nil, let waiting) = state else { return }
                state = .reading(progress, waiting: waiting)
            }
        }

        func deliver(_ piece: Piece?) {
            let waiting: CheckedContinuation<Piece?, Never>? = state.withLock { state in
                guard case .reading(_, let waiting) = state else { return nil }
                state = .done(piece)
                return waiting
            }
            waiting?.resume(returning: piece)
        }

        func piece() async -> Piece? {
            await withCheckedContinuation { continuation in
                let done: Piece?? = state.withLock { state in
                    switch state {
                    case .reading(let progress, _):
                        state = .reading(progress, waiting: continuation)
                        return nil
                    case .done(let piece):
                        return .some(piece)
                    }
                }
                if let done { continuation.resume(returning: done) }
            }
        }

        /// Stops copying the file, which may be a long video or come from iCloud. The provider then delivers nothing.
        func cancel() {
            let progress: Progress? = state.withLock { state in
                guard case .reading(let progress, _) = state else { return nil }
                return progress
            }
            progress?.cancel()
        }
    }
}
