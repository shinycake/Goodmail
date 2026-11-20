import IMAPProvider
import MailCore
import MailUI

/// Signing in to an account on any IMAP and SMTP server.
extension AccountSignIn {
    /// Presents the other account form over the chooser, and returns whether it added the account.
    func signInToOtherAccount() async -> Bool {
        await presentSignIn { [model] finished in
            OtherAccountSignInScreen.make(
                discover: { await MailServerDiscovery().settings(for: $0) },
                guess: MailServerDiscovery.guess(for:),
                signIn: { email, name, settings, password in
                    do {
                        try await model.addIMAPAccount(email: email, name: name, settings: settings, password: password)
                    } catch let failure as IMAPSignIn.Failure {
                        throw OtherAccountSignInFailure(failure) ?? failure
                    }
                },
                finished: finished)
        }
    }
}

extension OtherAccountSignInFailure {
    /// The form's failure for the sign-in's; `nil` for a missing login, which a sign-in doesn't throw.
    init?(_ failure: IMAPSignIn.Failure) {
        func side(_ server: IMAPSignIn.Server) -> Server {
            switch server {
            case .imap: .incoming
            case .smtp: .outgoing
            }
        }
        switch failure {
        case .refused(let server): self = .refused(side(server))
        case .insecure(let server): self = .insecure(side(server))
        case .unreachable(let server): self = .unreachable(side(server))
        case .signedOut: return nil
        }
    }
}
