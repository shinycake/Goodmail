public import MailCore

/// The choices the mail screens are built from, which change only by rebuilding them: the accounts, the Inboxes not
/// sorted into categories, how rows look, and what the combined views wear. A window compares the ones it was built
/// from with the ones now; the open Settings screen says when the reader changes them (`SettingsViewModel`).
public struct MailScreenChoices: Equatable, Sendable {
    public let accounts: [Account]
    public let unsortedInboxAccounts: Set<AccountID>
    public let rowDisplay: RowDisplay
    public let theme: CombinedTheme

    public init(
        accounts: [Account], unsortedInboxAccounts: Set<AccountID>, rowDisplay: RowDisplay, theme: CombinedTheme
    ) {
        self.accounts = accounts
        self.unsortedInboxAccounts = unsortedInboxAccounts
        self.rowDisplay = rowDisplay
        self.theme = theme
    }
}
