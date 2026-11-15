import UIKit

/// How Pin and Unpin read and look, wherever they are offered.
enum PinPresentation {
    /// "Pin" when `pin`, else "Unpin".
    static func title(_ pin: Bool) -> String {
        pin
            ? String(
                localized: "Pin", table: "Pin", bundle: .module,
                comment: "Action: keep a thread at the top of its list")
            : String(
                localized: "Unpin", table: "Pin", bundle: .module,
                comment: "Action: let a pinned thread go back to its place in the list")
    }

    static func symbol(_ pin: Bool) -> String {
        pin ? "pin" : "pin.slash"
    }
}

extension UIBarButtonItem {
    /// Pin, or with `pin` false Unpin, for the selected threads.
    static func pin(_ pin: Bool, _ handler: @escaping () -> Void) -> UIBarButtonItem {
        UIBarButtonItem(
            title: PinPresentation.title(pin), image: UIImage(systemName: PinPresentation.symbol(pin)),
            primaryAction: UIAction { _ in handler() })
    }
}
