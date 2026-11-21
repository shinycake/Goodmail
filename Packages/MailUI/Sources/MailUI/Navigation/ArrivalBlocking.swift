import SwiftUI
public import UIKit

/// A screen an arrival from outside must not take down, since the reader is in the middle of answering it: a sign-in,
/// a transfer between devices, or the other devices' accounts on offer. A `UIAlertController`, an alert or a
/// confirmation, counts as one too. The arrival lands beneath it (R3).
public protocol ArrivalBlocking: UIViewController {}

/// A SwiftUI screen an arrival leaves up.
final class ArrivalBlockingHost<Content: View>: UIHostingController<Content>, ArrivalBlocking {}

/// What an arrival from outside may clear of what is presented over a window.
public enum Uncovering {
    /// Whether any of `presented`, the screens presented over the window bottom to top, must stay, so that none of
    /// them is dismissed: one over a sheet that stays belongs to it, as an alert over Settings does.
    public static func blocks(_ presented: [UIViewController]) -> Bool {
        presented.contains { $0 is UIAlertController || $0 is any ArrivalBlocking }
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
}
