import MailCore
import MailUI

/// Bringing back the accounts this device had before the app was deleted. Their sign-ins and this device's record of
/// each stay in its Keychain (`AccountSharing.remember`), so a new install offers them back.
extension AppModel {
    /// The accounts a window offers without a sign-in (`AccountOffer`).
    var accountOffer: AccountOffer? {
        // A device that follows the others adds their accounts by itself; only one that offers asks.
        let elsewhere = AccountSharingMode.current == .offering ? sharedElsewhere : []
        return AccountOffer(
            restorable: restorable, elsewhere: elsewhere, declined: Preferences.declinedSharedAccounts)
    }

    /// Adds the accounts the reader chose from the offer and turns down the rest. Choosing any the other devices
    /// have follows them from now on, as their offer does; restoring this device's own changes nothing else.
    func addOfferedAccounts(_ chosen: [AccountID], declining declined: [AccountID]) async throws {
        let restoring = restorable.filter { chosen.contains($0.id) }
        // Read before the restored accounts are here, which takes them out of it.
        let followsOthers = chosen.contains { id in sharedElsewhere.contains { $0.id == id } }
        try await adopt(restoring)
        if followsOthers {
            try await addSharedAccounts(chosen, declining: declined)
        } else {
            Preferences.declinedSharedAccounts.formUnion(declined)
            await shareAccounts()
            await syncAfterAdding()
        }
    }
}
