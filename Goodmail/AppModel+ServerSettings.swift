import IMAPProvider
import MailCore
import MailUI

extension AppModel {
    /// The sign-in of an account that logs in with a password, as Settings edits it: an Other Mail Account's servers
    /// and password, or iCloud's app-specific password. `nil` for Gmail and Outlook, which sign in with their
    /// service. Saving logs in before keeping the change, then serves the account with it.
    func serverSettingsService(for id: AccountID) -> ServerSettingsEditor.Service? {
        guard let account = accounts.first(where: { $0.id == id }) else { return nil }
        switch account.service {
        case .imap:
            return ServerSettingsEditor.Service(
                kind: .servers,
                load: {
                    let login = try IMAPSignIn(secrets: Keychain.signIns()).login(for: id)
                    return ServerSettingsEditor.Login(settings: login.settings, password: login.password)
                },
                save: { [weak self] login in
                    guard let settings = login.settings else { return }
                    do {
                        try await self?.addIMAPAccount(
                            email: account.email, name: account.name, settings: settings, password: login.password)
                    } catch let failure as IMAPSignIn.Failure {
                        throw OtherAccountSignInFailure(failure) ?? failure
                    }
                })
        case .icloud:
            return ServerSettingsEditor.Service(
                kind: .appPassword,
                load: {
                    ServerSettingsEditor.Login(
                        settings: nil, password: try ICloudSignIn(secrets: Keychain.signIns()).appPassword(for: id))
                },
                save: { [weak self] login in
                    do {
                        try await self?.addICloudAccount(email: account.email, appPassword: login.password)
                    } catch ICloudSignIn.Failure.wrongPassword {
                        throw OtherAccountSignInFailure.refused(.incoming)
                    }
                })
        case .gmail, .outlook:
            return nil
        }
    }
}
