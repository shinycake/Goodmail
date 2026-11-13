import UIKit

/// Asks for an iCloud address and an app-specific password, which is how iCloud Mail lets another app in.
public enum ICloudSignInPrompt {
    /// The address and password, or `nil` if the reader cancelled.
    public struct Credentials: Equatable, Sendable {
        public let email: String
        public let appPassword: String
    }

    @MainActor
    public static func ask(from presenter: UIViewController) async -> Credentials? {
        await withCheckedContinuation { continuation in
            let alert = UIAlertController(
                title: String(localized: "iCloud Mail", bundle: .module, comment: "Title of the iCloud sign-in form"),
                message: String(
                    localized:
                        "Use an app-specific password, made at account.apple.com under Sign-In and Security.",
                    bundle: .module, comment: "Explains where to get an iCloud app-specific password"),
                preferredStyle: .alert)
            alert.addTextField { field in
                field.placeholder = String(
                    localized: "name@icloud.com", bundle: .module, comment: "Placeholder of the iCloud address field")
                field.keyboardType = .emailAddress
                field.textContentType = .username
                field.autocapitalizationType = .none
                field.autocorrectionType = .no
            }
            alert.addTextField { field in
                field.placeholder = String(
                    localized: "App-Specific Password", bundle: .module,
                    comment: "Placeholder of the iCloud app-specific password field")
                field.isSecureTextEntry = true
                field.textContentType = .password
            }
            alert.addAction(
                UIAlertAction(
                    title: String(localized: "Cancel", bundle: .module, comment: "Cancels signing in"),
                    style: .cancel
                ) { _ in continuation.resume(returning: nil) })
            alert.addAction(
                UIAlertAction(
                    title: String(localized: "Sign In", bundle: .module, comment: "Signs in to iCloud Mail"),
                    style: .default
                ) { [weak alert] _ in
                    let fields = alert?.textFields ?? []
                    let email = (fields.first?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    let password = (fields.last?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    continuation.resume(
                        returning: email.isEmpty || password.isEmpty
                            ? nil : Credentials(email: email, appPassword: password))
                })
            presenter.present(alert, animated: true)
        }
    }
}
