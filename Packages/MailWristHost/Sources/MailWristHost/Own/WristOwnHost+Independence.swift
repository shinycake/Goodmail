import Foundation
import MailCore
import MailStore
import MailWrist

extension WristOwnHost {
    /// How each served account's check went, by account.
    typealias Outcomes = [AccountID: Result<Void, any Error>]

    /// The owner's switch (ADR-023) and the work of the stretch it is on. Off, the watch serves no account: nothing
    /// syncs, sends or shows a footer. Each stretch on serves its own accounts, so work begun in an earlier one can
    /// tell the switch moved since.
    enum Independence {
        /// Off. `ending` ends once the last stretch's work has, its checks stopped and its changes through, and the
        /// watch has given back what didn't go and forgotten its copy, or failed to and left both for the next start.
        case off(ending: Task<Void, Never>?)
        case on(Stretch)

        /// The switch's position.
        var position: WristIndependence {
            switch self {
            case .off: .off
            case .on: .on
            }
        }

        /// The stretch on now, if the switch is on.
        var stretch: Stretch? {
            guard case .on(let stretch) = self else { return nil }
            return stretch
        }

        /// The accounts the watch reads itself now: none while off.
        var served: [AccountID: Served] { stretch?.served ?? [:] }

        /// Changes the stretch `id`, if it is still the one on.
        private mutating func update(_ id: Stretch.ID, _ change: (inout Stretch) -> Void) {
            guard case .on(var stretch) = self, stretch.id == id else { return }
            change(&stretch)
            self = .on(stretch)
        }

        /// Starts serving `account` with `served` in the stretch `id`, unless it serves the account already.
        mutating func serve(_ account: AccountID, with served: Served, in id: Stretch.ID) {
            update(id) { stretch in
                if stretch.served[account] == nil { stretch.served[account] = served }
            }
        }

        /// Stops serving `account`, as when it leaves the watch.
        mutating func stopServing(_ account: AccountID) {
            guard let id = stretch?.id else { return }
            update(id) { $0.served[account] = nil }
        }

        /// Readies the stretch `id` again with `start`, after its first try failed.
        mutating func restart(_ id: Stretch.ID, with start: Task<Void, any Error>) {
            update(id) { $0.start = start }
        }

        /// Keeps `check`, running in the stretch `id`, so that the switch going off stops it.
        mutating func track(_ check: Task<Outcomes, Never>, as checkID: UUID, in id: Stretch.ID) {
            update(id) { $0.checks[checkID] = check }
        }

        /// The check `checkID` of the stretch `id` ended, having worked for at least one account at `date`, or with
        /// `nil` when it didn't or was cut short. A later date is never replaced by an earlier one.
        mutating func finishCheck(_ checkID: UUID, in id: Stretch.ID, workedAt date: Date?) {
            update(id) { stretch in
                stretch.checks[checkID] = nil
                stretch.lastChecked = [stretch.lastChecked, date].compactMap(\.self).max()
            }
        }

        /// Keeps `change`, a command the reader made in the stretch `id`, so that the switch going off waits for it.
        mutating func track(_ change: Change, as changeID: UUID, in id: Stretch.ID) {
            update(id) { $0.changes[changeID] = change }
        }

        /// The change `changeID` of the stretch `id` ended.
        mutating func finishChange(_ changeID: UUID, in id: Stretch.ID) {
            update(id) { $0.changes[changeID] = nil }
        }
    }

    /// A stretch of the switch being on.
    struct Stretch: Identifiable {
        /// How a stretch readies the watch's copy before serving it.
        enum Readying {
            /// At launch, the copy is as the watch left it: only what a handover left undelivered is delivered.
            case asLeft
            /// After the switch was off: what the stretch before left undone is given back, then each account's sync
            /// starts afresh and nothing queued before the switch went off goes out.
            case afresh
        }

        let id = UUID()
        let readying: Readying
        /// Readies the watch's copy as `readying` says, after the stretch before has ended. Serving waits for it, and
        /// tries it again when it failed.
        var start: Task<Void, any Error>
        var served: [AccountID: Served] = [:]
        /// The checks running, which the switch going off stops.
        var checks: [UUID: Task<Outcomes, Never>] = [:]
        /// When a check in this stretch last worked for at least one account, if one has.
        var lastChecked: Date?
        /// The reader's changes being made, which the switch going off lets finish, so each knows whether it went.
        var changes: [UUID: Change] = [:]
    }

    /// A change the reader made, being made.
    struct Change {
        /// The command's ID, which its record in the database and the intents it queues carry.
        let command: UUID
        let task: Task<ChangeOutcome, any Error>
    }

    /// How a change the reader made ended at the service.
    enum ChangeOutcome: Sendable {
        case went
        /// Queued for the next sync or catch-up, as offline.
        case queued
        /// A reply's upload hasn't settled; the next flush asks the service before sending again.
        case uploading
        /// A reply that couldn't go, taken back.
        case notSent
    }

    /// Moves the owner's switch, the one place it moves. Off, it stops the stretch's checks; once they and its
    /// changes have ended, the watch gives back what didn't go and forgets its copy. On again, it waits for that,
    /// and does it again, before serving.
    func turn(_ position: WristIndependence) {
        switch (independence, position) {
        case (.on, .on), (.off, .off):
            return
        case (.on(let stretch), .off):
            for check in stretch.checks.values { check.cancel() }
            // Owned by `.off`, and awaited by the next stretch's start. It ends on its own: the checks were cancelled,
            // the outboxes stop before their next intent, and each change ends at its service. What it fails to give
            // back, the next start gives back. The senders aren't stopped: each sends only within a check or a change.
            independence = .off(
                ending: Task {
                    for served in stretch.served.values { await served.outbox.stopDraining() }
                    await end(stretch)
                })
        case (.off(let ending), .on):
            // Again: a change made just as the switch went off may have been queued after the first time.
            independence = .on(
                Stretch(
                    readying: .afresh,
                    start: Task {
                        await ending?.value
                        try await ready(.afresh)
                    }))
        }
    }

    /// Ends `stretch` once its work has, then gives back what it left undone and forgets the copy.
    private func end(_ stretch: Stretch) async {
        _ = await stretch.start.result
        for check in stretch.checks.values { _ = await check.value }
        for change in stretch.changes.values { _ = await change.task.result }
        // A failure keeps the changes and the copy, for the next start to give back and forget.
        do {
            try await settle(served: stretch.served)
        } catch {
            Self.log.error("Couldn't give back the watch's changes and forget its copy", error)
        }
    }
}
