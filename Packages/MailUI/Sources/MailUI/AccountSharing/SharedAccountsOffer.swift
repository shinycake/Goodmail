public import MailCore
public import Observation

/// Accounts offered to this device without signing in, because their sign-ins are in the Keychain already: set up on
/// the reader's other devices, or on this one before the app was deleted. Each starts chosen.
@Observable
public final class SharedAccountsOffer {
    public enum State: Equatable {
        /// Waiting for the reader to choose.
        case choosing
        /// Adding the chosen accounts.
        case adding
    }

    public let accounts: [Account]
    public let origin: AccountOffer.Origin
    public var chosen: Set<AccountID>
    public private(set) var state = State.choosing
    /// The last add that failed, for the view to show.
    public var error: (any Error)?
    /// Runs once the reader added accounts or put the offer off, set by whoever shows it.
    @ObservationIgnored public var onFinished: () -> Void = {}
    @ObservationIgnored private let add: (_ chosen: [AccountID], _ declined: [AccountID]) async throws -> Void
    @ObservationIgnored private let decline: ([AccountID]) -> Void

    /// `add` adds the chosen accounts and remembers the rest as declined; `decline` remembers them all, so the offer
    /// doesn't come back on its own. Settings still lists them.
    public init(
        accounts: [Account], origin: AccountOffer.Origin = .otherDevices,
        add: @escaping (_ chosen: [AccountID], _ declined: [AccountID]) async throws -> Void,
        decline: @escaping ([AccountID]) -> Void
    ) {
        self.accounts = accounts
        self.origin = origin
        chosen = Set(accounts.map(\.id))
        self.add = add
        self.decline = decline
    }

    /// Adds the chosen accounts, in the offer's order.
    public func addChosen() async {
        guard state == .choosing else { return }
        state = .adding
        defer { state = .choosing }
        let ids = accounts.map(\.id)
        do {
            try await add(ids.filter(chosen.contains), ids.filter { !chosen.contains($0) })
            onFinished()
        } catch {
            self.error = error
        }
    }

    public func notNow() {
        decline(accounts.map(\.id))
        onFinished()
    }
}
