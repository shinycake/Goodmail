import Synchronization

/// What `AccountSessions` keeps for an account: everything that talks to its service on one sign-in, which `end()`
/// stops once the account signs in afresh or goes.
public protocol LiveSession: AnyObject, Sendable {
    /// Stops what still runs on the old sign-in, so none of it outlives the change.
    func end() async
}

/// Each account's live session, the one owner of what talks to its service on one sign-in. A session is made from
/// the account's stored sign-in on first use and shared until `replace` or `remove`, which end it, so nothing goes
/// on with an old password or token once the reader changed it.
public final class AccountSessions<Session: LiveSession>: Sendable {
    public enum Failure: Error, Equatable {
        /// The account was removed, or is being removed, and gets no new session until it's added again.
        case removed
    }

    private enum State {
        /// Made from the stored sign-in on next use.
        case unmade
        case live(Session)
        case removed
    }

    private struct Slot {
        var state = State.unmade
        /// Counts the account's changes of sign-in, so a session made from one that changed while it was being made
        /// isn't kept.
        var generation = 0
    }

    private let make: @Sendable (AccountID) throws -> Session
    private let slots = Mutex<[AccountID: Slot]>([:])

    /// `make` builds an account's session from its stored sign-in, throwing when there's none. It runs outside
    /// the lock, since it reads the Keychain.
    public init(make: @escaping @Sendable (AccountID) throws -> Session) {
        self.make = make
    }

    public func session(for id: AccountID) throws -> Session {
        while true {
            let slot = slots.withLock { $0[id, default: Slot()] }
            switch slot.state {
            case .live(let session): return session
            case .removed: throw Failure.removed
            case .unmade: break
            }
            let made = Result { try make(id) }
            let kept: Session? = try slots.withLock { slots in
                var now = slots[id, default: Slot()]
                // The sign-in changed while this one was made, so what it made or threw is stale; look again.
                guard now.generation == slot.generation else { return nil }
                // Another caller made one first.
                if case .live(let session) = now.state { return session }
                let session = try made.get()
                now.state = .live(session)
                slots[id] = now
                return session
            }
            if let kept { return kept }
        }
    }

    /// The sessions made so far, as for stopping what each runs.
    public var live: [AccountID: Session] {
        slots.withLock { slots in
            slots.compactMapValues { if case .live(let session) = $0.state { session } else { nil } }
        }
    }

    /// Serves the account with `session` from now on, as after a sign-in that made it; with `nil`, with one made
    /// from its stored sign-in on next use, as after that changed. Ends the one it had, and brings back a removed
    /// account.
    public func replace(_ id: AccountID, with session: Session? = nil) async {
        await move(id, to: session.map(State.live) ?? .unmade)?.end()
    }

    /// Ends the account's session and makes no new one, so nothing reads or writes its sign-in while it goes.
    public func remove(_ id: AccountID) async {
        await move(id, to: .removed)?.end()
    }

    /// The one place a sign-in changes: puts `state` in place and returns the session it replaces.
    private func move(_ id: AccountID, to state: State) -> Session? {
        slots.withLock { slots in
            var slot = slots[id, default: Slot()]
            defer {
                slot.state = state
                slot.generation += 1
                slots[id] = slot
            }
            guard case .live(let session) = slot.state else { return nil }
            return session
        }
    }
}
