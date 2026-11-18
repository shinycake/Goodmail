import UIKit

extension MailboxViewController {
    /// Opens the paper plane game over the window from the Inbox Zero scene's tenth tap. The game draws the envelopes,
    /// doodles and planes from this frame on, so the scene stops drawing them, and hands them back as it leaves.
    ///
    /// Crossing between a wide and a narrow window builds the Inbox anew, scene and all, under the game. So the game
    /// asks the window each time for the Inbox that shows now, rather than keeping this one.
    func playPlaneGame(from handoff: InboxZeroHandoff) {
        guard inboxZero != nil, presentedViewController == nil, let window = view.window,
            let stage = inWindow(handoff.stage)
        else { return }
        let inbox = { [weak window] in window.flatMap(MailboxViewController.showingInbox(in:)) }
        // The planes in the air fly in the window's sky, which hands them over as they were at the tenth tap.
        var sky: InboxZeroSkyHandoff?
        if case .running(let tapped) = handoff.scene.clock {
            sky = (splitViewController as? MailSplitViewController)?.inboxZeroSky.handoff(
                at: tapped, rightToLeft: handoff.scene.rightToLeft)
        }
        let game = PlaneGameViewController(
            handoff: InboxZeroHandoff(scene: handoff.scene, stage: stage, sky: sky), window: window,
            list: PlaneGameList(
                stage: { inbox()?.planeGameStage() },
                threads: { inbox()?.planeGameThreads() ?? 0 }),
            // The game says so every frame; the scene's state changes only on the first.
            takeOver: { inbox()?.inboxZero?.setPlaying(true) },
            handBack: { inbox()?.inboxZero?.setPlaying(false) })
        present(game, animated: false)
    }

    /// The Inbox list on display in `window`, under anything presented over it, or `nil` when none is, as when a
    /// narrow window shows the mailboxes or a thread.
    private static func showingInbox(in window: UIWindow) -> MailboxViewController? {
        var stack = window.rootViewController.map { [$0] } ?? []
        while let controller = stack.popLast() {
            if let mailbox = controller as? MailboxViewController, mailbox.inboxZero != nil,
                mailbox.viewIfLoaded?.window === window
            {
                return mailbox
            }
            stack.append(contentsOf: controller.children)
        }
        return nil
    }

    /// Where the scene's envelopes and doodles are on the screen now, or `nil` when no scene shows because the Inbox
    /// has mail again.
    private func planeGameStage() -> InboxZeroStage? {
        guard let inboxZero, inboxZero.showing != nil, let stage = inboxZero.stage else { return nil }
        return inWindow(stage)
    }

    /// How many threads the list shows: mail that arrived during the game, since it began on an empty Inbox.
    private func planeGameThreads() -> Int {
        (0..<collectionView.numberOfSections).reduce(0) { $0 + collectionView.numberOfItems(inSection: $1) }
    }
}
