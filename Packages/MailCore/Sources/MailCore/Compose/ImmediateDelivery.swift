public import Foundation
import Synchronization

#if canImport(FoundationNetworking)
    public import FoundationNetworking  // URLSession on Linux
#endif

/// Sends or saves one message at once, for a process that is gone before a background upload could report back, as
/// the Share extension is once its sheet closes. The message goes through a `Sender` of its own, over a queue that
/// holds it alone (`PrivateQueue`), so the shared queue isn't touched while it goes and the app can't take a message
/// the extension is sending, nor the extension one of the app's. Whatever doesn't finish here goes into the shared
/// queue as it was left, for the app to finish by the queue's own rules: still to go, gone without an answer (which
/// the app settles by asking the service, later, once its search has caught up), or refused (which the app shows the
/// writer). It is handed over exactly once: when the attempt ends, or earlier, when the process is about to be
/// suspended (`handOver()`). Once handed over, nothing more is attempted here; only a direct send already on the wire
/// then can still go, and go again from the app, the same window a launch killed mid-send leaves.
public final class ImmediateDelivery: Sendable {
    public enum Outcome: Equatable, Sendable {
        /// It went: sent, or saved in the provider's Drafts.
        case done
        /// It didn't finish here, and waits in the shared queue as `delivery`.
        case handedOver(OutgoingMessage.Delivery)
    }

    /// The message couldn't be put in the shared queue, so it is nowhere but here.
    public struct NotKept: Error {
        /// Whether it may have reached the service anyway, so sending it again could send it twice.
        public let mayHaveGone: Bool

        public init(mayHaveGone: Bool) {
            self.mayHaveGone = mayHaveGone
        }
    }

    private enum Stage {
        /// Under way, or not started.
        case going
        /// Ended, with what was left given to the shared queue, or nothing left at all.
        case handedOver(Outcome)
    }

    private let accountID: AccountID
    private let provider: any MailProvider
    private let store: any OutgoingStore
    private let queue: PrivateQueue
    private let uploads: InlineUploads
    private let sender: Sender
    private let stage = Mutex(Stage.going)

    /// Sends `draft`, or saves it in the provider's Drafts, through `provider`. Upload bodies are written under
    /// `scratch`, a folder of the caller's own.
    public init(
        _ draft: Draft, as purpose: OutgoingMessage.Purpose, provider: any MailProvider, store: any OutgoingStore,
        http: any HTTPClient = URLSession.shared, scratch: URL, now: @escaping @Sendable () -> Date = { .now }
    ) {
        accountID = draft.accountID
        self.provider = provider
        self.store = store
        queue = PrivateQueue(holding: [OutgoingMessage(draft: draft, purpose: purpose, sendAt: now())], over: store)
        uploads = InlineUploads(http: http)
        sender = Sender(
            accountID: draft.accountID, provider: provider, store: queue, transport: uploads, uploads: scratch,
            now: now)
    }

    /// Makes the one attempt, then hands over what's left. Throws `NotKept` when that couldn't be put in `store`.
    @concurrent public func run() async throws -> Outcome {
        await sender.flush()
        for (id, outcome) in uploads.takeOutcomes(of: accountID) where !needsAsking(outcome) {
            _ = await sender.complete(id, with: outcome)
        }
        return try handOver()
    }

    /// Gives the shared queue what's left now, as the process is about to be suspended mid-attempt, or once the
    /// attempt is over. Later calls return the first one's outcome.
    @discardableResult
    public func handOver() throws -> Outcome {
        try stage.withLock { stage in
            if case .handedOver(let outcome) = stage { return outcome }
            guard let left = queue.takeAll().first else {
                stage = .handedOver(.done)
                return .done
            }
            do {
                try store.enqueue(left)
            } catch {
                throw NotKept(mayHaveGone: left.delivery != .queued)
            }
            stage = .handedOver(.handedOver(left.delivery))
            return .handedOver(left.delivery)
        }
    }

    /// An answer that says nothing about whether the message went is left for the app to settle by asking the
    /// service later: asked now, a message that went can be missing from search for a while yet, and would be
    /// reported unconfirmed and sent again.
    private func needsAsking(_ outcome: UploadOutcome) -> Bool {
        guard case .response(let status, let body) = outcome, case .upload(let sending) = provider.sending else {
            return true
        }
        return sending.answer(status: status, body: body) == .unknown
    }
}
