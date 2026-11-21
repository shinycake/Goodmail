import QuickLook
public import UIKit

/// A screen an arrival from outside may take down, since it only reads or picks and the reader loses nothing by it:
/// Settings, the label, move and later pickers, a letter's sheet. Quick Look and the share sheet count too. Anything
/// else presented over a window, an alert, a confirmation, a sign-in, a transfer or the accounts offer, or a screen
/// nobody marked, stays up, and the arrival lands beneath it (R3).
public protocol ArrivalDismissible: UIViewController {}

/// What an arrival from outside may clear of what is presented over a window.
public enum ArrivalCover {
    /// Whether every one of `presented`, the screens presented over the window bottom to top, may be dismissed. One
    /// that may not keeps all of them up: one over it belongs to it, as an alert over Settings does.
    public static func dismissible(_ presented: [UIViewController]) -> Bool {
        presented.allSatisfy(isDismissible)
    }

    /// The screens presented over `root`, bottom to top.
    public static func presented(over root: UIViewController) -> [UIViewController] {
        var screens: [UIViewController] = []
        var top = root
        while let next = top.presentedViewController {
            screens.append(next)
            top = next
        }
        return screens
    }

    private static func isDismissible(_ screen: UIViewController) -> Bool {
        if screen is any ArrivalDismissible || screen is QLPreviewController || screen is UIActivityViewController {
            return true
        }
        // The pickers come in a navigation controller of their own.
        guard let navigation = screen as? UINavigationController, let root = navigation.viewControllers.first else {
            return false
        }
        return root is any ArrivalDismissible
    }
}

extension LabelPickerViewController: ArrivalDismissible {}
extension MoveViewController: ArrivalDismissible {}
extension LaterPickerViewController: ArrivalDismissible {}
extension LetterSheetController: ArrivalDismissible {}
