import IMAPProvider
import MailCore
import MailUI
import UIKit

/// Signing in to an account over one window: a mail window's, or the Settings window's. Each service's web page or
/// form shows over whatever is frontmost in that window, as the service chooser in Settings or on the welcome screen.
struct AccountSignIn {
    let model: AppModel
    /// The window the sign-in shows over. Weak, since Settings keeps this for as long as it is up, and the window
    /// holds Settings.
    private(set) weak var window: UIWindow?

    init(model: AppModel, window: UIWindow) {
        self.model = model
        self.window = window
    }

    /// Signs in to `service` and adds its account. Returns `false` if the reader cancelled, or the window is gone. A
    /// service whose sign-in is a web page goes through `AppModel`; one that needs its own form presents it here, over
    /// the chooser.
    func signIn(to service: MailService) async throws -> Bool {
        guard let web else { return false }
        switch service {
        case .gmail: return try await model.addGmailAccount(using: web)
        case .icloud: return await signInToICloud()
        case .outlook: return try await model.addOutlookAccount(using: web)
        case .imap: return await signInToOtherAccount()
        }
    }

    /// The web sign-in over the window, while there is one: the forms need it too.
    var web: WebAuthentication? { window.map(WebAuthentication.init) }

    /// Presents the iCloud form over the chooser, and returns whether it added the account.
    /// `email` fills the address in, as when iCloud stopped accepting an account's password.
    func signInToICloud(email: String = "") async -> Bool {
        await presentSignIn { [model] finished in
            ICloudSignInScreen.make(
                email: email,
                signIn: { email, appPassword in
                    do {
                        try await model.addICloudAccount(email: email, appPassword: appPassword)
                    } catch ICloudSignIn.Failure.wrongPassword {
                        throw ICloudSignInFailure.wrongPassword
                    }
                },
                finished: finished)
        }
    }

    /// Presents a sign-in form `screen` makes over the chooser, and returns what the form finished with: whether it
    /// added the account. The form calls `finished` once.
    func presentSignIn(_ screen: (_ finished: @escaping (Bool) -> Void) -> UIViewController) async -> Bool {
        await withCheckedContinuation { continuation in
            weak var presented: UIViewController?
            let form = screen { added in
                presented?.dismiss(animated: true)
                continuation.resume(returning: added)
            }
            presented = form
            guard let top = window?.topViewController else { return continuation.resume(returning: false) }
            top.present(form, animated: true)
        }
    }
}

extension UIWindow {
    /// What shows frontmost in the window: its root, or what is presented over it.
    var topViewController: UIViewController? {
        var top = rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
