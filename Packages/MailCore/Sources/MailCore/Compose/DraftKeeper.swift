public import Foundation
import Synchronization

extension OutgoingMessage {
    /// How long a draft being written waits in the queue before it goes on to the provider. It is on the device after
    /// every edit; the provider gets it at most this often.
    public static let autosaveWait: Duration = .seconds(20)

    /// The save autosave queues for `draft` at `now`, due once `wait` passes.
    public static func autosave(_ draft: Draft, after wait: Duration = autosaveWait, at now: Date) -> OutgoingMessage {
        OutgoingMessage(
            draft: draft, purpose: .saveDraft, sendAt: now.addingTimeInterval(Double(wait.components.seconds)))
    }
}

/// Keeps one message in the shared queue as it is written, from a process that doesn't drain the queue itself (the
/// Share extension, ADR-030), so the app finds it as a draft however that process ends. Each version is the save
/// the app's own composer queues as it autosaves (`OutgoingStore.enqueueSave`).
///
/// Writes go one at a time, off the caller's actor, in the order asked. A version asked for while one is being written
/// waits, and a newer one takes its place: a draft carries its files, so a backlog of whole copies would only cost
/// memory and time for versions nobody needs. Each write runs through `keepAwake`, which gives it the time a process
/// has to finish as it leaves the screen.
public final class DraftKeeper: Sendable {
    /// What the queue should hold for the message.
    public enum Version: Sendable {
        /// The message as written, for the app to save in Drafts by `date`.
        case written(Draft, by: Date)
        /// The writer deleted it: the waiting save is taken back, and the copy the app saved, if any, removed.
        case deleted(Draft)
    }

    /// Runs one write and returns once it is done or was given no time to run.
    public typealias KeepAwake = @Sendable (_ write: @escaping @Sendable () -> Void) async -> Void

    private enum State {
        case idle
        /// `task` is writing; `next` is the newest version asked for since, to write after it.
        case writing(Task<Void, Never>, next: Version?)
    }

    private let store: any OutgoingStore
    private let keepAwake: KeepAwake
    private let state = Mutex(State.idle)

    public init(store: any OutgoingStore, keepAwake: @escaping KeepAwake = { $0() }) {
        self.store = store
        self.keepAwake = keepAwake
    }

    /// Writes `version`, after the one being written if any. Errors are dropped: the version before stays queued, and
    /// the next edit tries again.
    public func keep(_ version: Version) {
        state.withLock { state in
            switch state {
            case .idle: state = .writing(Task { await self.write(from: version) }, next: nil)
            case .writing(let task, _): state = .writing(task, next: version)
            }
        }
    }

    /// Waits for every version asked for so far.
    public func settle() async {
        let task = state.withLock { state -> Task<Void, Never>? in
            guard case .writing(let task, _) = state else { return nil }
            return task
        }
        await task?.value
    }

    /// Takes back the save waiting for `draft`, as the process sends or saves the message itself: what was queued, to
    /// put back if that fails. Call after `settle`. The app may be saving that version at the same moment, since a
    /// save stays queued while it goes; its copy is then either recorded in time for the process's own save or send to
    /// replace or remove, or left in Drafts.
    public func take(_ draft: Draft.ID) -> OutgoingMessage? {
        try? store.cancel(draft)
    }

    /// Puts back what `take` took, when the process couldn't finish the message itself.
    public func restore(_ message: OutgoingMessage) {
        keep(.written(message.draft, by: message.sendAt))
    }

    @concurrent private func write(from first: Version) async {
        var version = first
        while true {
            let store = store
            let writing = version
            await keepAwake { Self.write(writing, to: store) }
            let next = state.withLock { state -> Version? in
                guard case .writing(let task, let next) = state else { return nil }
                state = next == nil ? .idle : .writing(task, next: nil)
                return next
            }
            guard let next else { return }
            version = next
        }
    }

    private static func write(_ version: Version, to store: any OutgoingStore) {
        switch version {
        case .written(let draft, let date):
            try? store.enqueueSave(OutgoingMessage(draft: draft, purpose: .saveDraft, sendAt: date))
        case .deleted(let draft):
            _ = try? store.cancel(draft.id)
            // Only a copy the app already saved needs the app to remove it.
            guard (try? store.savedCopy(of: draft.id)) != nil else { return }
            try? store.enqueue(OutgoingMessage(draft: draft, purpose: .deleteDraft, sendAt: .now))
        }
    }
}
