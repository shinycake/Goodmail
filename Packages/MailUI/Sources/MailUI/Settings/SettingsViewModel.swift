import Foundation
public import MailCore
public import Observation
import SwiftUI

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
    /// Which actions sit on each side of a mailbox row.
    public var swipeArrangement: SwipeArrangement {
        didSet { Preferences.swipeArrangement = swipeArrangement }
    }
    /// What each swipe action's button wears.
    public var swipeTints: SwipeTints {
        didSet { Preferences.swipeTints = swipeTints }
    }
    /// How conversations open.
    public var conversationLayout: ConversationLayout {
        didSet { Preferences.conversationLayout = conversationLayout }
    }
    /// How trashed, archived and deleted threads leave the list.
    public var removalAnimation: RemovalAnimation {
        didSet { Preferences.removalAnimation = removalAnimation }
    }
    /// What views that span accounts wear.
    public var combinedTheme: CombinedTheme {
        didSet { Preferences.combinedTheme = combinedTheme }
    }
    /// Each account's signature.
    public let signatures: Signatures
    /// Each account's alerts; `nil` in builds without push.
    public var notifications: NotificationChoices?
    /// What each account counts toward the app badge.
    public var badges: BadgeChoices?
    /// The mail rules, when the app keeps them.
    @ObservationIgnored public var rules: MailRules.Service?
    /// The automatic reply of an account whose service sends one; `nil` for one that doesn't, as iCloud.
    @ObservationIgnored public var autoReply: (AccountID) -> AutoReplyEditor.Service? = { _ in nil }
    /// The sign-in of an account that logs in with a password: an Other Mail Account's servers and password, or
    /// iCloud's app-specific password; `nil` for an account that signs in with its service, as Gmail and Outlook do.
    @ObservationIgnored public var serverSettings: (AccountID) -> ServerSettingsEditor.Service? = { _ in nil }
    /// This device's part in sharing accounts with the reader's other devices; `nil` where accounts aren't shared,
    /// as in synthetic mailboxes.
    @ObservationIgnored public var sharing: AccountSharingChoices? {
        didSet { sharing?.onAccountsChanged = { [weak self] in self?.refresh() } }
    }
    /// Moving accounts to or from another device by QR code; `nil` where accounts can't be moved, as in synthetic
    /// mailboxes.
    @ObservationIgnored public var transfer: TransferActions?
    /// Accounts whose Inbox isn't split into categories.
    public var unsortedInboxAccounts: Set<AccountID> {
        didSet { Preferences.unsortedInboxAccounts = unsortedInboxAccounts }
    }

    @ObservationIgnored private let remove: (AccountID, AccountRemoval) async throws -> Void
    @ObservationIgnored private let update: (Account) async throws -> Void
    @ObservationIgnored private let reorder: ([AccountID]) async throws -> Void
    /// Stores name, color and order changes in the order the reader made them (`change`).
    @ObservationIgnored private let changes = TaskChain()
    /// The changes not stored yet, oldest first. The screen shows the stored accounts with these applied.
    @ObservationIgnored private var pending: [Change] = []
    @ObservationIgnored private let reload: () -> [Account]
    @ObservationIgnored private let closed: () -> Void

    /// `signIn` signs in to a service and adds its account, returning `false` if the reader cancelled; `remove`
    /// takes an account and its mail off this device, or off every device that shares accounts; `update` stores an account's new name or color; `reorder`
    /// stores the order the reader put the accounts in. `accounts` reads them back after each. `signatures` reads and saves each account's signature; a failure shows as `error`.
    /// `closed` runs once the screen is gone, however it was dismissed.
    public init(
        accounts: @escaping () -> [Account],
        signIn: @escaping (MailService) async throws -> Bool,
        remove: @escaping (AccountID, AccountRemoval) async throws -> Void,
        update: @escaping (Account) async throws -> Void,
        reorder: @escaping ([AccountID]) async throws -> Void = { _ in },
        signatures: Signatures = Signatures(read: { _ in nil }, store: { _, _ in }),
        closed: @escaping () -> Void
    ) {
        self.accounts = accounts()
        adder = AccountAdder(signIn: signIn)
        undoSendSeconds = Preferences.undoSendSeconds
        rowDisplay = Preferences.rowDisplay
        swipeArrangement = Preferences.swipeArrangement
        swipeTints = Preferences.swipeTints
        conversationLayout = Preferences.conversationLayout
        removalAnimation = Preferences.removalAnimation
        unsortedInboxAccounts = Preferences.unsortedInboxAccounts
        combinedTheme = Preferences.combinedTheme
        reload = accounts
        self.remove = remove
        self.update = update
        self.reorder = reorder
        self.closed = closed
        self.signatures = signatures
        adder.onAdded = { [weak self] in self?.refresh() }
        signatures.failed = { [weak self] in self?.error = $0 }
    }

    /// Takes the account and its mail off this device, or every device that shares accounts, once the changes asked
    /// for before it are stored; a change asked for after it finds no account to store. A failure shows as `error`;
    /// `settled()` waits for it.
    public func removeAccount(_ id: AccountID, _ removal: AccountRemoval = .thisDevice) {
        changes.run { [self] in
            do {
                try await remove(id, removal)
            } catch {
                self.error = error
            }
            refresh()
            sharing?.refresh()
        }
    }

    /// Sends the account's mail under `name`, without its surrounding spaces; a blank name sends the address alone.
    func rename(_ id: AccountID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        change(.edit(id) { $0.name = trimmed.isEmpty ? nil : trimmed })
    }

    /// Names the account `nickname` in the app, without its surrounding spaces; a blank one shows its address again.
    func setNickname(_ id: AccountID, to nickname: String) {
        let trimmed = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        change(.edit(id) { $0.nickname = trimmed.isEmpty ? nil : trimmed })
    }

    func setColor(_ color: AccountColor, for id: AccountID) {
        change(.edit(id) { $0.color = color })
    }

    /// Moves the accounts at `offsets` to before the one at `destination`, as a list's drag reports it.
    func moveAccounts(from offsets: IndexSet, to destination: Int) {
        var order = accounts.map(\.id)
        order.move(fromOffsets: offsets, toOffset: destination)
        change(.reorder(order))
    }

    /// Moves the account one place up (`by: -1`) or down (`by: 1`), as VoiceOver's actions do. Nothing at either end.
    func moveAccount(_ id: AccountID, by step: Int) {
        guard let index = accounts.firstIndex(where: { $0.id == id }), accounts.indices.contains(index + step) else {
            return
        }
        moveAccounts(from: [index], to: step > 0 ? index + step + 1 : index + step)
    }

    /// One change the reader made to the accounts.
    private enum Change {
        /// An edit of one account's name, nickname or color.
        case edit(AccountID, (inout Account) -> Void)
        /// The accounts in a new order. Any it doesn't name, as one added since, follow in the order they had.
        case reorder([AccountID])

        func apply(to accounts: inout [Account]) {
            switch self {
            case .edit(let id, let edit):
                guard let index = accounts.firstIndex(where: { $0.id == id }) else { return }
                edit(&accounts[index])
            case .reorder(let order):
                let rank = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
                // The sort is stable, so the accounts `order` leaves out keep their order after the ones it names.
                accounts.sort { rank[$0.id, default: order.count] < rank[$1.id, default: order.count] }
            }
        }
    }

    /// Shows the change at once and stores it after any change before it. Each one is applied, when its turn
    /// comes, to the accounts as stored, so a rename and a color change made in quick succession both stick, and
    /// one that fails is shown and carried by no later change.
    private func change(_ change: Change) {
        pending.append(change)
        refresh()
        changes.run { [self] in
            // The chain runs changes in the order they were appended, so this one is first. It stays pending, and
            // shown, until it is stored or has failed.
            let change = pending[0]
            let before = reload()
            var after = before
            change.apply(to: &after)
            do {
                try await store(change, from: before, to: after)
            } catch {
                self.error = error
            }
            pending.removeFirst()
            refresh()
        }
    }

    /// Stores what `change` made of the stored accounts, if it made anything of them.
    private func store(_ change: Change, from before: [Account], to after: [Account]) async throws {
        switch change {
        case .edit(let id, _):
            guard let account = after.first(where: { $0.id == id }), !before.contains(account) else { return }
            try await update(account)
        case .reorder:
            let order = after.map(\.id)
            guard order != before.map(\.id) else { return }
            try await reorder(order)
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
