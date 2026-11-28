public import MailCore
public import Observation

/// Accounts offered to this device without signing in, because their sign-ins are in the Keychain already: set up on
/// the reader's other devices, or on this one before the app was deleted. Each starts chosen.
@Observable
public final class SharedAccountsOffer {
    public enum State {
        /// Waiting for the reader to choose; `failure` is the last add that failed, shown until dismissed.
        case choosing(failure: (any Error)?)
        /// Adding the chosen accounts, in a task the offer owns: it stays open on a failure and closes once finished.
        case adding(Task<Void, Never>)
        /// The reader added the accounts or put the offer off, so it closes.
        case finished
    }

    public let accounts: [Account]
    public let origin: AccountOffer.Origin
    public var chosen: Set<AccountID>
    public private(set) var state = State.choosing(failure: nil)
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

    var isAdding: Bool {
        if case .adding = state { true } else { false }
    }

    var isFinished: Bool {
        if case .finished = state { true } else { false }
    }

    /// The last add that failed, for the alert.
    var failure: (any Error)? {
        if case .choosing(let failure) = state { failure } else { nil }
    }

    /// Adds the chosen accounts, in the offer's order. Ignored unless the reader is choosing.
    public func addChosen() {
        guard case .choosing = state else { return }
        let ids = accounts.map(\.id)
        let (picked, declined) = (ids.filter(chosen.contains), ids.filter { !chosen.contains($0) })
        state = .adding(Task { await self.run(adding: picked, declining: declined) })
    }

    /// Waits for the add under way, if any, as a test does.
    func settled() async {
        if case .adding(let adding) = state { await adding.value }
    }

    private func run(adding picked: [AccountID], declining declined: [AccountID]) async {
        do {
            try await add(picked, declined)
            finish()
        } catch {
            state = .choosing(failure: error)
        }
    }

    public func notNow() {
        guard case .choosing = state else { return }
        decline(accounts.map(\.id))
        finish()
    }

    /// The reader read the failure.
    func dismissFailure() {
        guard case .choosing(.some) = state else { return }
        state = .choosing(failure: nil)
    }

    private func finish() {
        state = .finished
        onFinished()
    }
}
