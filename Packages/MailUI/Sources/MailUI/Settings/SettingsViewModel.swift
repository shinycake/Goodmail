import Foundation
import MailCore
import Observation

/// The accounts on this device and the reader's choices.
@Observable
public final class SettingsViewModel {
    public private(set) var accounts: [Account]
    /// Adds accounts from the Add Account screen.
    public let adder: AccountAdder
    /// The last remove or change that failed, for the view to show.
    public var error: (any Error)?
    public var undoSendSeconds: Int {
        didSet { Preferences.undoSendSeconds = undoSendSeconds }
    }
    /// How mailbox rows look.
    public var rowDisplay: RowDisplay {
        didSet { Preferences.rowDisplay = rowDisplay }
    }
    /// How conversations open.
    public var conversationLayout: ConversationLayout {
        didSet { Preferences.conversationLayout = conversationLayout }
    }
    /// What views that span accounts wear.
    public var combinedTheme: CombinedTheme {
        didSet { Preferences.combinedTheme = combinedTheme }
    }
    /// Each account's alerts; `nil` in builds without push.
    public var notifications: NotificationChoices?
    /// Accounts whose Inbox isn't split into categories.
    public var unsortedInboxAccounts: Set<AccountID> {
        didSet { Preferences.unsortedInboxAccounts = unsortedInboxAccounts }
    }

    @ObservationIgnored private let remove: (AccountID) async throws -> Void
    @ObservationIgnored private let update: (Account) async throws -> Void
    /// Stores name and color changes in the order the reader made them (`change`).
    @ObservationIgnored private let changes = TaskChain()
    /// The changes not stored yet, oldest first. The screen shows the stored accounts with these applied.
    @ObservationIgnored private var pending: [Change] = []
    @ObservationIgnored private let reload: () -> [Account]
    @ObservationIgnored private let closed: () -> Void

    /// `signIn` signs in to a service and adds its account, returning `false` if the reader cancelled; `remove`
    /// takes an account and its mail off the device; `update` stores an account's new name or color. `accounts`
    /// reads them back after each. `closed` runs once the screen is gone, however it was dismissed.
    public init(
        accounts: @escaping () -> [Account],
        signIn: @escaping (MailService) async throws -> Bool,
        remove: @escaping (AccountID) async throws -> Void,
        update: @escaping (Account) async throws -> Void,
        closed: @escaping () -> Void
    ) {
        self.accounts = accounts()
        adder = AccountAdder(signIn: signIn)
        undoSendSeconds = Preferences.undoSendSeconds
        rowDisplay = Preferences.rowDisplay
        conversationLayout = Preferences.conversationLayout
        unsortedInboxAccounts = Preferences.unsortedInboxAccounts
        combinedTheme = Preferences.combinedTheme
        reload = accounts
        self.remove = remove
        self.update = update
        self.closed = closed
        adder.onAdded = { [weak self] in self?.refresh() }
    }

    public func removeAccount(_ id: AccountID) async {
        do {
            try await remove(id)
        } catch {
            self.error = error
        }
        refresh()
    }

    /// Sends the account's mail under `name`, without its surrounding spaces; a blank name sends the address alone.
    func rename(_ id: AccountID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        change(id) { $0.name = trimmed.isEmpty ? nil : trimmed }
    }

    func setColor(_ color: AccountColor, for id: AccountID) {
        change(id) { $0.color = color }
    }

    /// One edit of one account's name or color.
    private struct Change {
        let id: AccountID
        let edit: (inout Account) -> Void

        func apply(to accounts: inout [Account]) {
            guard let index = accounts.firstIndex(where: { $0.id == id }) else { return }
            edit(&accounts[index])
        }
    }

    /// Shows the change at once and stores it after any change before it. Each one is applied, when its turn
    /// comes, to the account as stored, so a rename and a color change made in quick succession both stick, and
    /// one that fails is shown and carried by no later change.
    private func change(_ id: AccountID, _ edit: @escaping (inout Account) -> Void) {
        pending.append(Change(id: id, edit: edit))
        refresh()
        changes.run { [self] in
            // The chain runs changes in the order they were appended, so this one is first. It stays pending, and
            // shown, until it is stored or has failed.
            let change = pending[0]
            var stored = reload()
            let before = stored.first { $0.id == change.id }
            change.apply(to: &stored)
            if let account = stored.first(where: { $0.id == change.id }), account != before {
                do {
                    try await update(account)
                } catch {
                    self.error = error
                }
            }
            pending.removeFirst()
            refresh()
        }
    }

    /// Shows the stored accounts with the changes that aren't stored yet.
    private func refresh() {
        var shown = reload()
        for change in pending { change.apply(to: &shown) }
        accounts = shown
    }

    /// Waits until the changes made so far are stored.
    func settled() async {
        await changes.settled()
    }

    /// Whether views that span accounts wear the gradient. Turning it off starts from the first account's color.
    var wearsGradient: Bool {
        get { combinedTheme == .gradient }
        set { combinedTheme = newValue ? .gradient : .solid(accounts.first?.color ?? .blue) }
    }

    /// The gradient that views spanning accounts wear while `wearsGradient` is on.
    var gradient: AccountBlend { AccountBlend(accounts.map(\.color)) }

    /// The accounts whose service sorts its Inbox into categories, which the Inbox Categories switch covers.
    var categorisedAccounts: [Account] { accounts.filter(\.service.hasInboxCategories) }

    /// Whether the account's Inbox is split into Gmail's categories.
    func sortsInbox(_ account: AccountID) -> Bool {
        !unsortedInboxAccounts.contains(account)
    }

    func setSortsInbox(_ sorts: Bool, for account: AccountID) {
        if sorts {
            unsortedInboxAccounts.remove(account)
        } else {
            unsortedInboxAccounts.insert(account)
        }
    }

    /// Runs `closed` once the changes made so far are stored, so it sees them.
    func didClose() {
        changes.run { [closed] in closed() }
    }

    /// "Off", or the wait as a short duration.
    static func undoSendTitle(_ seconds: Int) -> String {
        guard seconds > 0 else {
            return String(
                localized: "Undo Send: Off", defaultValue: "Off", table: "Settings", bundle: .module,
                comment: "Undo Send is turned off")
        }
        return Duration.seconds(seconds).formatted(.units(allowed: [.seconds], width: .wide))
    }
}
