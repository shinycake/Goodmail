public import MailCore
public import Observation

/// This device's part in sharing accounts with the reader's other devices, as Settings shows it: whether it syncs,
/// and the shared accounts it doesn't have, any of which the reader can add.
@Observable
public final class AccountSharingChoices {
    /// Each change runs in a task the choices own, so it goes on when the page is left.
    public enum State {
        /// Nothing under way; `failure` is the last change that failed, shown until the reader dismisses it.
        case idle(failure: (any Error)?)
        /// Turning syncing on or off.
        case switching(Task<Void, Never>)
        /// Adding the account from the other devices.
        case adding(AccountID, Task<Void, Never>)
    }

    public private(set) var mode: AccountSharingMode
    /// Accounts set up on the reader's other devices and not on this one.
    public private(set) var elsewhere: [Account]
    public private(set) var state = State.idle(failure: nil)
    /// Runs after this device's accounts changed, so the screen showing them reads them again.
    @ObservationIgnored var onAccountsChanged: () -> Void = {}
    @ObservationIgnored private let setMode: (AccountSharingMode) async throws -> Void
    @ObservationIgnored private let addShared: (AccountID) async throws -> Void
    @ObservationIgnored private let reload: () -> (AccountSharingMode, [Account])

    /// `setMode` keeps the device's new mode and brings it in step with the other devices; `add` adds one of their
    /// accounts here; `reload` reads the mode and the other devices' accounts again after each.
    public init(
        reload: @escaping () -> (AccountSharingMode, [Account]),
        setMode: @escaping (AccountSharingMode) async throws -> Void,
        add: @escaping (AccountID) async throws -> Void
    ) {
        (mode, elsewhere) = reload()
        self.reload = reload
        self.setMode = setMode
        addShared = add
    }

    /// Whether this device syncs its accounts with the others.
    public var syncs: Bool { mode.shares }

    /// Whether a change is under way, so the others wait.
    var isBusy: Bool {
        if case .idle = state { false } else { true }
    }

    /// Whether `id` is the account being added.
    func isAdding(_ id: AccountID) -> Bool {
        if case .adding(id, _) = state { true } else { false }
    }

    /// The last change that failed, for the alert.
    var failure: (any Error)? {
        if case .idle(let failure) = state { failure } else { nil }
    }

    /// The reader read the failure.
    func dismissFailure() {
        guard case .idle(.some) = state else { return }
        state = .idle(failure: nil)
    }

    /// Turning syncing on follows the other devices from then on; turning it off keeps every account here as it is.
    public func setSyncs(_ syncs: Bool) {
        guard !isBusy else { return }
        state = .switching(Task { await self.run { try await self.setMode(syncs ? .following : .off) } })
    }

    public func add(_ id: AccountID) {
        guard !isBusy else { return }
        state = .adding(id, Task { await self.run { try await self.addShared(id) } })
    }

    /// Waits for the change under way, if any, as a test does.
    func settled() async {
        switch state {
        case .idle: break
        case .switching(let change), .adding(_, let change): await change.value
        }
    }

    /// Reads the mode and the other devices' accounts again, as after an account was removed from this device.
    func refresh() {
        (mode, elsewhere) = reload()
    }

    private func run(_ work: () async throws -> Void) async {
        do {
            try await work()
            state = .idle(failure: nil)
        } catch {
            state = .idle(failure: error)
        }
        refresh()
        onAccountsChanged()
    }
}
