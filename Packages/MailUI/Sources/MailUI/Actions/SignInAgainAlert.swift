import UIKit

extension UIAlertController {
    /// Asks a Gmail account whose sign-in predates Delete Forever to sign in again, which Gmail needs before it
    /// deletes mail for good (ADR-019). `signIn` runs only on Sign In.
    public static func signInAgainToDeleteForever(_ email: String, signIn: @escaping () -> Void) -> UIAlertController {
        let alert = UIAlertController(
            title: String(
                localized: "Sign In Again to Delete Forever", table: "DeleteForever", bundle: .module,
                comment: "Title of the alert asking a Gmail account to sign in again so it can delete mail for good"),
            message: String(
                localized: "Gmail needs \(email) to sign in again before it deletes mail forever.",
                table: "DeleteForever", bundle: .module,
                comment: "Message of the alert asking a Gmail account to sign in again, with its address"),
            preferredStyle: .alert)
        alert.addAction(
            UIAlertAction(
                title: String(
                    localized: "Not Now", table: "DeleteForever", bundle: .module,
                    comment: "Button: leaves the account signed in as it is"),
                style: .cancel))
        let signInAction = UIAlertAction(
            title: String(
                localized: "Sign In", table: "DeleteForever", bundle: .module,
                comment: "Button: opens Google's sign-in page for the account"),
            style: .default
        ) { _ in signIn() }
        alert.addAction(signInAction)
        alert.preferredAction = signInAction
        return alert
    }
}
