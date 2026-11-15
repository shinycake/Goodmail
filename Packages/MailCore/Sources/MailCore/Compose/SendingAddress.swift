/// An address a message can go from: an account's own, or one of its aliases.
public struct SendingAddress: Hashable, Sendable {
    public let account: Account
    /// `nil` for the account's own address.
    public let alias: Contact?

    public init(account: Account, alias: Contact? = nil) {
        self.account = account
        self.alias = alias
    }

    public var email: String { alias?.address ?? account.email }

    /// The addresses `draft` can go from, each account's own before its aliases. New mail can go from any of
    /// `accounts`; a reply, forward or saved draft stays in its own account, whose thread or Drafts it belongs to.
    public static func choices(for draft: Draft, among accounts: [Account]) -> [SendingAddress] {
        let staysInItsAccount = draft.threadID != nil || draft.savedDraft != nil
        return accounts.filter { !staysInItsAccount || $0.id == draft.accountID }.flatMap { account in
            [SendingAddress(account: account)] + account.aliases.map { SendingAddress(account: account, alias: $0) }
        }
    }
}
