import SwiftUI
import UIKit

extension MailSplitViewController {
    /// The view drawing an empty Inbox's paper planes over the columns. It takes no touches.
    func makeInboxZeroSkyView() -> UIView {
        let sky = UIHostingConfiguration { InboxZeroSkyView(sky: inboxZeroSky) }.margins(.all, 0).makeContentView()
        sky.isUserInteractionEnabled = false
        sky.clipsToBounds = true
        sky.accessibilityElementsHidden = true
        return sky
    }

    /// Keeps the sky over the list and the pane beside it, above the columns and below the undo toast, which is
    /// brought up after it. The columns come and go under it as the window changes size, so it is brought up on every
    /// layout.
    func placeInboxZeroSky() {
        let frame = inboxZeroSkyFrame
        if inboxZeroSkyView.frame != frame { inboxZeroSkyView.frame = frame }
        view.bringSubviewToFront(inboxZeroSkyView)
        let inWindow = view.convert(frame, to: nil)
        if inboxZeroSky.frame != inWindow { inboxZeroSky.frame = inWindow }
        // A column can move without laying out, as when a tiled sidebar slides in and pushes the list over, so the
        // list and the pane say again where they are in the window.
        (shownController(in: .supplementary) as? MailboxViewController)?.placeInboxZero()
        (shownController(in: .secondary) as? NoThreadViewController)?.placeInWindow()
    }

    /// The whole window when one screen fills it. Side by side, from the list's leading edge, or from beside the
    /// mailboxes when they are shown, tiled or floating over the list, to the far edge of the pane beside it while no
    /// message is open there, the window's full height: planes cross the list and the empty pane, never the mailboxes
    /// or a message.
    private var inboxZeroSkyFrame: CGRect {
        guard !isCollapsed, let list = shownView(in: .supplementary) else { return view.bounds }
        let insets = list.safeAreaInsets
        var frame = list.convert(
            list.bounds.inset(by: UIEdgeInsets(top: 0, left: insets.left, bottom: 0, right: insets.right)), to: view)
        // The pane only while it is empty: planes never cross an open message.
        if let pane = shownController(in: .secondary) as? NoThreadViewController {
            frame = frame.union(pane.view.convert(pane.view.bounds, to: view))
        }
        // A sidebar floating over the list isn't always in the list's safe area, so it is cut away by its own frame.
        if let sidebar = shownView(in: .primary).map({ $0.convert($0.bounds, to: view) }), sidebar.intersects(frame) {
            if sidebar.midX < frame.midX {
                frame = CGRect(x: sidebar.maxX, y: frame.minY, width: max(frame.maxX - sidebar.maxX, 0), height: 0)
            } else {
                frame = CGRect(x: frame.minX, y: frame.minY, width: max(sidebar.minX - frame.minX, 0), height: 0)
            }
        }
        return CGRect(x: frame.minX, y: view.bounds.minY, width: frame.width, height: view.bounds.height)
    }

    /// The view of the screen on top in `column`, while it is on show.
    private func shownView(in column: Column) -> UIView? {
        shownController(in: column)?.view
    }

    /// The screen on top in `column`, while it is on show.
    private func shownController(in column: Column) -> UIViewController? {
        let shown = viewController(for: column)
        let top = (shown as? UINavigationController)?.topViewController ?? shown
        guard let top, top.viewIfLoaded?.window != nil else { return nil }
        return top
    }
}
