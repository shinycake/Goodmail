import MailCore
import MailStore
public import MailWrist

extension WristOwnHost {
    /// Takes the iPhone's account list and the owner's switch, as each snapshot from the iPhone carries them. An
    /// account the iPhone no longer has leaves the watch with its mail and its copy of the sign-in, even one removed
    /// while the watch app wasn't running.
    public func follow(_ accounts: [WristAccount], independence: WristIndependence) throws {
        let kept = Set(accounts.map(\.id))
        for gone in try database.accounts() where !kept.contains(gone.id) { try drop(gone) }
        for account in accounts {
            guard let service = account.service, WristSignIns.client(for: account) != nil else { continue }
            try database.save(Account(id: account.id, email: account.address, color: account.color, service: service))
        }
        self.accounts = accounts
        turn(independence)
        publishFreshness()
    }

    private func drop(_ account: Account) throws {
        independence.stopServing(account.id)
        health[account.id] = nil
        try database.removeAccount(account.id)
        try signIns.forget(
            WristAccount(
                id: account.id, address: account.email, color: account.color, unread: 0, service: account.service))
    }
}
