import Foundation
import MailCore
import MailUI
import OSLog

/// Sharing accounts with the reader's other devices through iCloud Keychain. Each device shares its accounts and
/// their sign-ins; a new device offers the others' accounts, and once the reader accepts, or turns syncing on in
/// Settings, accounts added or removed on one device follow on the rest (`AccountSharingMode`).
extension AppModel {
    /// Posted after each pass that brought this device in step with the others, so each window shows the accounts
    /// that are here now and offers the ones that aren't.
    static let sharedAccountsDidUpdate = Notification.Name("GoodmailSharedAccountsDidUpdate")

    /// Where accounts are shared, while this device shares them.
    var activeSharing: AccountSharing? { AccountSharingMode.current.shares ? sharing : nil }

    /// The accounts the other devices share that this one doesn't have, as the last pass found them.
    var sharedElsewhere: [Account] { sharingFindings.elsewhere(besides: accounts) }

    /// Accounts this device had before the app was deleted, whose sign-ins are still in its Keychain
    /// (`AccountSharing.restorable`), and that it doesn't have again yet.
    var restorable: [Account] { sharingFindings.restorable(besides: accounts) }

    /// Brings this device in step with the others: takes up renames, and, when it follows them, adds and removes
    /// accounts as they did, then shares what only this device has. Passes run one at a time, each after the last.
    func followSharedAccounts() async throws {
        while let running = sharingPass { _ = await running.result }
        let pass = Task { try await runSharingPass() }
        sharingPass = pass
        defer { sharingPass = nil }
        // The pass stops with its caller, as the foreground sync rounds when the app goes to the background. A pass
        // waiting behind it then runs as usual.
        try await withTaskCancellationHandler {
            try await pass.value
        } onCancel: {
            pass.cancel()
        }
    }

    /// Adds the accounts the reader chose from the offer, turns down the rest, and follows the other devices from
    /// now on.
    func addSharedAccounts(_ chosen: [AccountID], declining declined: [AccountID]) async throws {
        Preferences.declinedSharedAccounts = Preferences.declinedSharedAccounts.subtracting(chosen).union(declined)
        AccountSharingMode.current = .following
        try await followSharedAccounts()
        await syncAfterAdding()
    }

    /// Adds one account from the other devices, as from Settings, even one the reader turned down before.
    func addSharedAccount(_ id: AccountID) async throws {
        Preferences.declinedSharedAccounts.remove(id)
        guard let account = sharedElsewhere.first(where: { $0.id == id }) else { return }
        try await adopt([account])
        try await followSharedAccounts()
        await syncAfterAdding()
    }

    /// Keeps how this device takes part from now on, and brings it in step with the others at once.
    func setSharingMode(_ mode: AccountSharingMode) async throws {
        AccountSharingMode.current = mode
        try await followSharedAccounts()
        if mode == .following { await syncAfterAdding() }
    }

    /// What Settings shows and changes of sharing.
    func sharingChoices() -> AccountSharingChoices? {
        guard sharing != nil else { return nil }
        return AccountSharingChoices(
            reload: { [weak self] in (AccountSharingMode.current, self?.sharedElsewhere ?? []) },
            setMode: { [weak self] in try await self?.setSharingMode($0) },
            add: { [weak self] in try await self?.addSharedAccount($0) })
    }

    /// The ID another device gave this address at this service, so signing in to an account the reader's other
    /// devices have makes it the same account rather than a second one.
    func sharedID(of service: MailService, _ email: String) -> AccountID? {
        sharedElsewhere.first { $0.service == service && $0.email.caseInsensitiveCompare(email) == .orderedSame }?.id
    }

    /// After the reader signed in to the account here: it's no longer turned down or only elsewhere, and the other
    /// devices get it with its new sign-in.
    func didSignIn(_ id: AccountID) async {
        Preferences.declinedSharedAccounts.remove(id)
        await shareAccounts()
    }

    /// Forgets the account's sign-in: this device's copy alone, or the shared one too once `removeAccount` told the
    /// other devices it was removed. An account removed from this device only isn't taken back on its own.
    func signOut(_ account: Account, _ removal: AccountRemoval) async {
        if removal == .thisDevice, activeSharing != nil { Preferences.declinedSharedAccounts.insert(account.id) }
        // Each goes on its own, since either one gone keeps a reinstall from offering the account back.
        do {
            try await sharing?.forget(account.id)
        } catch {
            Logger.sharing.error("Couldn't forget an account's record: \(error, privacy: .public)")
        }
        do {
            try await Self.forgetSignIn(of: account, everywhere: removal == .everyDevice)
        } catch {
            Logger.sharing.error("Couldn't sign an account out: \(error, privacy: .public)")
        }
    }

    /// Off the main actor, since the Keychain blocks.
    @concurrent private nonisolated static func forgetSignIn(of account: Account, everywhere: Bool) async throws {
        try Providers.signOut(account, from: everywhere ? Keychain.signIns() : Keychain())
    }

    /// Shares this device's accounts, in their order, with the other devices. A failure waits for the next pass.
    func shareAccounts() async {
        do {
            // Remembered on this device whether or not it shares, so a reinstall can bring them back.
            try await sharing?.remember(accounts)
        } catch {
            Logger.sharing.error("Couldn't remember the accounts: \(error, privacy: .public)")
        }
        do {
            try await activeSharing?.share(accounts)
        } catch {
            Logger.sharing.error("Couldn't share the accounts: \(error, privacy: .public)")
        }
    }

    private func runSharingPass() async throws {
        defer { NotificationCenter.default.post(name: Self.sharedAccountsDidUpdate, object: self) }
        do {
            sharingFindings.found(restorable: try await sharing?.restorable(for: accounts) ?? [])
        } catch {
            // Only the offer after a reinstall needs it, so the rest of the pass goes on.
            Logger.sharing.error("Couldn't read the accounts to restore: \(error, privacy: .public)")
        }
        guard let sharing = activeSharing else {
            await shareAccounts()
            sharingFindings.found(elsewhere: [])
            return
        }
        let plan = try await sharing.plan(for: accounts)
        if AccountSharingMode.current == .following {
            for id in plan.removedElsewhere where accounts.contains(where: { $0.id == id }) {
                try await removeAccount(id, .everyDevice)
            }
            let declined = Preferences.declinedSharedAccounts
            try await adopt(plan.missing.filter { !declined.contains($0.id) })
        }
        // Taken up here first and shared once at the end, so this device's stale copy of a name or the order
        // never goes back over what another device changed.
        for account in plan.changedElsewhere where accounts.contains(where: { $0.id == account.id }) {
            try await keep(account)
        }
        let order = plan.order(of: accounts)
        if order != accounts.map(\.id) { try await keep(order: order) }
        await shareAccounts()
        sharingFindings.found(elsewhere: plan.missing)
    }
}

extension Logger {
    nonisolated static let sharing = Logger(subsystem: "com.idanbirman.goodmail", category: "sharing")
}
