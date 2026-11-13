import Foundation
import MailCore
import Observation

/// The accounts on this device and the reader's choices.
@Observable
public final class SettingsViewModel {
    public private(set) var accounts: [Account]
    public private(set) var isAddingAccount = false
    /// The last add or remove that failed, for the view to show.
    public var error: (any Error)?
    public var undoSendSeconds: Int {
        didSet { Preferences.undoSendSeconds = undoSendSeconds }
    }
    /// Accounts whose Inbox isn't split into categories.
    public var unsortedInboxAccounts: Set<AccountID> {
        didSet { Preferences.unsortedInboxAccounts = unsortedInboxAccounts }
    }

    @ObservationIgnored private let add: () async throws -> Bool
    @ObservationIgnored private let remove: (AccountID) async throws -> Void
    @ObservationIgnored private let update: (Account) throws -> Void
    @ObservationIgnored private let reload: () -> [Account]
    @ObservationIgnored private let closed: () -> Void

    /// `add` signs in another account and returns `false` if the reader cancelled; `remove` takes an account and
    /// its mail off the device; `update` stores an account's new name or color. `reload` reads the accounts back after
    /// each. `closed` runs once the screen is gone, however it was dismissed.
    public init(
        accounts: @escaping () -> [Account],
        add: @escaping () async throws -> Bool,
        remove: @escaping (AccountID) async throws -> Void,
        update: @escaping (Account) throws -> Void,
        closed: @escaping () -> Void
    ) {
        self.accounts = accounts()
        undoSendSeconds = Preferences.undoSendSeconds
        unsortedInboxAccounts = Preferences.unsortedInboxAccounts
        reload = accounts
        self.add = add
        self.remove = remove
        self.update = update
        self.closed = closed
    }

    public func addAccount() async {
        isAddingAccount = true
        defer { isAddingAccount = false }
        do {
            _ = try await add()
        } catch {
            self.error = error
        }
        accounts = reload()
    }

    public func removeAccount(_ id: AccountID) async {
        do {
            try await remove(id)
        } catch {
            self.error = error
        }
        accounts = reload()
    }

    /// Sends the account's mail under `name`, without its surrounding spaces; a blank name sends the address alone.
    func rename(_ id: AccountID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        change(id) { $0.name = trimmed.isEmpty ? nil : trimmed }
    }

    func setColor(_ color: AccountColor, for id: AccountID) {
        change(id) { $0.color = color }
    }

    /// Stores the change unless it leaves the account as it was.
    private func change(_ id: AccountID, _ edit: (inout Account) -> Void) {
        guard var account = accounts.first(where: { $0.id == id }) else { return }
        let before = account
        edit(&account)
        guard account != before else { return }
        do {
            try update(account)
        } catch {
            self.error = error
        }
        accounts = reload()
    }

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

    func didClose() {
        closed()
    }

    /// "Off", or the wait as a short duration.
    static func undoSendTitle(_ seconds: Int) -> String {
        guard seconds > 0 else {
            return String(
                localized: "Undo Send: Off", defaultValue: "Off", bundle: .module, comment: "Undo Send is turned off")
        }
        return Duration.seconds(seconds).formatted(.units(allowed: [.seconds], width: .wide))
    }
}
