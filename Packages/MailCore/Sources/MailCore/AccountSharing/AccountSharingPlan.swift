/// How this device's accounts differ from the ones the reader's devices share through iCloud Keychain. A device
/// that follows the others applies all of it; one that only offers asks before adding `missing` and keeps the
/// accounts removed elsewhere.
public struct AccountSharingPlan: Equatable, Sendable {
    /// Accounts another device shares, with their sign-in, that this device doesn't have, in the shared order.
    public let missing: [Account]
    /// This device's accounts that another device removed.
    public let removedElsewhere: [AccountID]
    /// This device's accounts as another device renamed, nicknamed or recolored them.
    public let changedElsewhere: [Account]
    /// Each shared account's place in the order the reader put them in.
    private let positions: [AccountID: Int]

    /// `local` is this device's accounts in order; `shared` the records found in iCloud Keychain. `signedIn` says
    /// whether an account's sign-in arrived: iCloud Keychain may bring a record before the sign-in beside it, and
    /// an account without one can't be added yet.
    public init(
        local: [Account], shared: [AccountID: SharedAccount], signedIn: (AccountID, MailService) -> Bool
    ) {
        let here = Set(local.map(\.id))
        let profiles = shared.compactMapValues(\.profile)
        positions = profiles.mapValues(\.position)
        missing = profiles.filter { id, profile in !here.contains(id) && signedIn(id, profile.service) }
            .sorted { ($0.value.position, $0.key.rawValue) < ($1.value.position, $1.key.rawValue) }
            .map { id, profile in profile.account(id) }
        removedElsewhere = local.filter { shared[$0.id] == .removed }.map(\.id)
        changedElsewhere = local.compactMap { account in
            guard let profile = profiles[account.id] else { return nil }
            var changed = account
            changed.name = profile.name
            changed.nickname = profile.nickname
            changed.color = AccountColor(rawValue: profile.color) ?? account.color
            return changed == account ? nil : changed
        }
    }

    /// `accounts` in the shared order: shared accounts by their place, then the ones only this device has, as
    /// they were.
    public func order(of accounts: [Account]) -> [AccountID] {
        accounts.enumerated()
            .sorted { (positions[$0.element.id] ?? .max, $0.offset) < (positions[$1.element.id] ?? .max, $1.offset) }
            .map(\.element.id)
    }
}
