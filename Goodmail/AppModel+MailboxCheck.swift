import Foundation
import GmailProvider
import MailCore
import MailUI
import OSLog

/// The push relay's look at a Gmail account's history, so it alerts only for new Inbox mail (PushWorker/README.md).
extension AppModel {
    /// The Settings switch for a Gmail account in a build with push; `nil` otherwise.
    func mailboxCheckService(for id: AccountID, using web: @escaping () -> WebAuthentication) -> MailboxCheck.Service? {
        guard pushRegistrar != nil, let relayURL = PushConfiguration.relayURL,
            let account = accounts.first(where: { $0.id == id }), account.service == .gmail
        else { return nil }
        let relay = PushRelayClient(baseURL: relayURL)
        return MailboxCheck.Service(
            isOn: { [weak self] in
                guard let client = self?.gmailClient(for: id) else { return nil }
                do {
                    return try await client.checksMailbox(relay: relay)
                } catch {
                    Logger.push.error("Couldn't ask the relay about its mailbox check: \(error, privacy: .public)")
                    return nil
                }
            },
            turnOn: { await Self.grantMailboxCheck(for: account.email, relay: relay, using: web()) },
            turnOff: { [weak self] in
                guard let client = self?.gmailClient(for: id) else { return false }
                do {
                    try await client.stopMailboxCheck(relay: relay)
                    return true
                } catch {
                    Logger.push.error("Couldn't turn the mailbox check off: \(error, privacy: .public)")
                    return false
                }
            })
    }

    private func gmailClient(for id: AccountID) -> GmailClient? {
        (try? providers.provider(for: id)) as? GmailClient
    }

    /// Google's consent page for the metadata grant, then the grant to the relay. `false` when the reader closed the
    /// page or it failed.
    private static func grantMailboxCheck(
        for email: String, relay: any MailboxCheckRelay, using web: WebAuthentication
    ) async -> Bool {
        let client = OAuthClient.gmailMailboxCheck
        let pkce = PKCE.generate()
        let state = UUID().uuidString
        do {
            let url = client.authorizationURL(pkce: pkce, state: state, loginHint: email)
            guard let redirect = try await web.authenticate(url: url, callbackScheme: client.redirectScheme)
            else { return false }
            let code = try OAuthClient.code(fromRedirect: redirect, expectedState: state)
            try await GmailClient.grantMailboxCheck(code: code, pkce: pkce, relay: relay)
            return true
        } catch {
            Logger.push.error("Couldn't turn the mailbox check on: \(error, privacy: .public)")
            return false
        }
    }
}
