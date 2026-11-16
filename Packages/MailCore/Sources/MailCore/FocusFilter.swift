/// Which accounts the views that blend every account show, as the current Focus sets it.
public enum FocusFilter: Hashable, Sendable {
    /// No Focus filter: every account shows.
    case everyAccount
    /// Only these accounts show in the blended views, and only they alert. Each account's own mailboxes stay open.
    case accounts(Set<AccountID>)

    /// Whether the account shows in the blended views and alerts.
    public func includes(_ account: AccountID) -> Bool {
        switch self {
        case .everyAccount: true
        case .accounts(let accounts): accounts.contains(account)
        }
    }
}
