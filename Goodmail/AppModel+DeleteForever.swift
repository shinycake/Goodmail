import GmailProvider
import MailCore

extension AppModel {
    /// Gmail accounts whose sign-in doesn't let Gmail delete mail for good, because it predates the full mail scope
    /// (ADR-019). An account that can't be checked now, as when offline, isn't listed.
    func gmailAccountsToSignInAgain() async -> [Account] {
        var stale: [Account] = []
        for account in accounts where account.service == .gmail {
            guard let gmail = try? providers.provider(for: account.id) as? GmailClient else { continue }
            if (try? await gmail.deletesForever()) == false { stale.append(account) }
        }
        return stale
    }
}
