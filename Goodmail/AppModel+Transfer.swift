import Foundation
import MailCore

/// Moving accounts between devices by QR code (`TransferHost`, `TransferNetwork`).
extension AppModel {
    /// The chosen accounts, in their order, with their sign-ins. Off the main actor: it reads the Keychain.
    @concurrent nonisolated static func transferPayload(of accounts: [Account], chosen: Set<AccountID>) async throws
        -> TransferPayload
    {
        let secrets = Keychain.signIns()
        var entries: [TransferPayload.Entry] = []
        for (position, account) in accounts.enumerated() where chosen.contains(account.id) {
            // An account whose sign-in is gone can't work on the other device either.
            guard let signIn = try secrets.data(for: Providers.signInKey(account.id, account.service)) else { continue }
            entries.append(.init(id: account.id, profile: .init(account, position: position), signIn: signIn))
        }
        return TransferPayload(entries: entries)
    }

    /// Adds the accounts another device sent, with their sign-ins, and syncs them. One already on this device, by ID
    /// or by address, is left as it is. Returns the accounts added.
    func addTransferred(_ payload: TransferPayload) async throws -> [Account] {
        let new = payload.entries(newTo: accounts)
        try await Self.keepSignIns(of: new)
        let added = new.map { $0.profile.account($0.id) }
        do {
            try await adopt(added)
        } catch {
            // The sign-ins of accounts that didn't make it in would be left with nothing to use them. Only this
            // device's copies go: a shared one may be another device's sign-in for the same account.
            let left = new.filter { entry in !accounts.contains { $0.id == entry.id } }
            try? await Self.forgetSignIns(of: left)
            throw error
        }
        for account in added { await didSignIn(account.id) }
        await syncAfterAdding()
        return added
    }

    @concurrent private nonisolated static func keepSignIns(of entries: [TransferPayload.Entry]) async throws {
        let secrets = Keychain.signIns()
        for entry in entries {
            try secrets.set(entry.signIn, for: Providers.signInKey(entry.id, entry.profile.service))
        }
    }

    @concurrent private nonisolated static func forgetSignIns(of entries: [TransferPayload.Entry]) async throws {
        let secrets = Keychain()
        for entry in entries { try secrets.remove(Providers.signInKey(entry.id, entry.profile.service)) }
    }
}
