public import Observation

/// The watch's Inbox screen: what the iPhone last sent, or why there is nothing to show.
@MainActor @Observable
public final class WristInboxModel {
    public enum State: Equatable, Sendable {
        /// Nothing has arrived from the iPhone yet.
        case waitingForPhone
        /// The iPhone's app is newer than this one and sends what this one can't read.
        case updateNeeded
        /// The iPhone has no mail accounts.
        case noAccounts
        /// The Inbox is empty.
        case caughtUp(WristSnapshot)
        case list(WristSnapshot)
    }

    public private(set) var state = State.waitingForPhone

    public init() {}

    /// Shows each snapshot as it arrives, until `readings` ends or the task is cancelled.
    public func follow(_ readings: some AsyncSequence<WristSnapshot.Reading, Never>) async {
        for await reading in readings { receive(reading) }
    }

    /// The one place `state` changes.
    public func receive(_ reading: WristSnapshot.Reading) {
        state =
            switch reading {
            case .newerVersion: .updateNeeded
            case .snapshot(let snapshot) where snapshot.accounts.isEmpty: .noAccounts
            case .snapshot(let snapshot) where snapshot.rows.isEmpty: .caughtUp(snapshot)
            case .snapshot(let snapshot): .list(snapshot)
            }
    }
}
