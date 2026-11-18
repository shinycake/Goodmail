import SwiftUI
public import UIKit

/// What the message column shows beside a list while no thread is open: "No Message Selected", or, beside an empty
/// Inbox, where there is nothing to select, the Inbox Zero scene's doodles carrying on across it.
public final class NoThreadViewController: UIViewController {
    private let pane = NoThreadPane()
    /// The split view this pane last showed in. Kept because by the time the pane has gone it may no longer be a child.
    private weak var split: MailSplitViewController?

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        let content = UIHostingConfiguration { NoThreadView(pane: pane) }.margins(.all, 0).makeContentView()
        content.frame = view.bounds
        content.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(content)
    }

    /// Nothing to act on, so no toolbar: each screen of a stack sets its own as it appears.
    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setToolbarHidden(true, animated: animated)
    }

    public override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        split = splitViewController as? MailSplitViewController
        pane.sky = split?.inboxZeroSky
        skyChanged()
    }

    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        skyChanged()
    }

    /// The window's sky reaches across this pane only while it shows, and swapping the column's screen doesn't lay the
    /// split view out, so the split is asked to place its sky again.
    private func skyChanged() {
        split?.view.setNeedsLayout()
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        placeInWindow()
    }

    /// Tells the pane where it is in the window, which the doodles and the touches on it are measured in.
    func placeInWindow() {
        let frame = view.convert(view.bounds, to: nil)
        if pane.frame != frame { pane.frame = frame }
        // Wider on the list's side, so the pane's doodles keep a clear gap from the ring's across the line.
        let towardList: CGFloat = 56
        let rightToLeft = view.effectiveUserInterfaceLayoutDirection == .rightToLeft
        let margins = UIEdgeInsets(
            top: 16, left: rightToLeft ? 24 : towardList, bottom: 16, right: rightToLeft ? towardList : 24)
        let field = view.convert(view.bounds.inset(by: view.safeAreaInsets).inset(by: margins), to: nil)
        if pane.field != field { pane.field = field }
    }
}
