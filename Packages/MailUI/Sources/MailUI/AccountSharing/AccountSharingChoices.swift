public import MailCore
public import Observation

/// This device's part in sharing accounts with the reader's other devices, as Settings shows it: whether it syncs,
/// and the shared accounts it doesn't have, any of which the reader can add.
@Observable
public final class AccountSharingChoices {
    public enum State: Equatable {
        case idle
        /// Turning syncing on or off.
        case switching
        /// Adding the account from the other devices.
        case adding(AccountID)
    }

    public private(set) var mode: AccountSharingMode
    /// Accounts set up on the reader's other devices and not on this one.
    public private(set) var elsewhere: [Account]
    public private(set) var state = State.idle
    /// The last change that failed, for the view to show.
    public var error: (any Error)?
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
        guard state == .idle else { return }
        state = next
        defer { state = .idle }
        do {
            try await work()
        } catch {
            self.error = error
        }
        refresh()
        onAccountsChanged()
    }
}
