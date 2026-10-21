import Dispatch
import notify

/// Tells the other processes sharing the database that it changed (ADR-002). GRDB observes only the writes made
/// through its own pool, so a process that hears another's signal re-checks its observations.
///
/// Darwin notifications carry no payload, so the sender's identity rides in the notification's shared state.
/// Two signals in quick succession can overwrite it; the worst case is one redundant or one skipped re-check, and
/// the skipped one is caught by the next signal or the next read.
final class ChangeSignal: Sendable {
    static let name = "com.idanbirman.goodmail.store-changed"

    private let id = UInt64.random(in: 1...UInt64.max)
    private let token: Int32

    /// `onForeignChange` runs on a private queue whenever a different `ChangeSignal`, in any process, posts.
    init(onForeignChange: @escaping @Sendable () -> Void) {
        var token: Int32 = 0
        let queue = DispatchQueue(label: "com.idanbirman.goodmail.store-changed")
        let ownID = id
        notify_register_dispatch(Self.name, &token, queue) { token in
            var sender: UInt64 = 0
            notify_get_state(token, &sender)
            if sender != ownID { onForeignChange() }
        }
        self.token = token
    }

    deinit {
        notify_cancel(token)
    }

    func post() {
        notify_set_state(token, id)
        notify_post(Self.name)
    }
}
