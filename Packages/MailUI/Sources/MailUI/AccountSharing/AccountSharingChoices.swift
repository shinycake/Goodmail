public import MailCore
public import Observation

/// This device's part in sharing accounts with the reader's other devices, as Settings shows it: whether it syncs,
/// and the shared accounts it doesn't have, any of which the reader can add.
@Observable
public final class AccountSharingChoices {
    public enum State {
        /// Nothing under way; `failure` is the last change that failed, shown until the reader dismisses it.
        case idle(failure: (any Error)?)
        /// Turning syncing on or off.
        case switching
        /// Adding the account from the other devices.
        case adding(AccountID)
    }

    public private(set) var mode: AccountSharingMode
    /// Accounts set up on the reader's other devices and not on this one.
    public private(set) var elsewhere: [Account]
    public private(set) var state = State.idle(failure: nil)
    /// Runs after this device's accounts changed, so the screen showing them reads them again.
    @ObservationIgnored var onAccountsChanged: () -> Void = {}
    @ObservationIgnored private let setMode: (AccountSharingMode) async throws -> Void
    @ObservationIgnored private let add: (AccountID) async throws -> Void
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
        self.add = add
    }

    /// Whether this device syncs its accounts with the others.
    public var syncs: Bool { mode.shares }

    /// Whether a change is under way, so the others wait.
    var isBusy: Bool {
        if case .idle = state { false } else { true }
    }

    /// Whether `id` is the account being added.
    func isAdding(_ id: AccountID) -> Bool {
        if case .adding(id) = state { true } else { false }
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
    public func setSyncs(_ syncs: Bool) async {
        await change(.switching) { try await setMode(syncs ? .following : .off) }
    }

    public func add(_ id: AccountID) async {
        await change(.adding(id)) { try await add(id) }
    }

    /// Reads the mode and the other devices' accounts again, as after an account was removed from this device.
    func refresh() {
        (mode, elsewhere) = reload()
    }

    private func change(_ next: State, _ work: () async throws -> Void) async {
        guard !isBusy else { return }
        state = next
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
