import UIKit

extension MailboxViewController {
    /// Opens the paper plane game over the window from the Inbox Zero scene's tenth tap. The game draws the envelopes,
    /// doodles and planes from this frame on, so the scene stops drawing them, and hands them back as it leaves.
    func playPlaneGame(from handoff: InboxZeroHandoff) {
        guard let inboxZero, presentedViewController == nil, let window = view.window,
            let stage = onScreen(handoff.stage)
        else { return }
        let game = PlaneGameViewController(
            handoff: InboxZeroHandoff(scene: handoff.scene, stage: stage), window: window,
            list: PlaneGameList(
                stage: { [weak self] in self?.planeGameStage() },
                threads: { [weak self] in self?.planeGameThreads() ?? 0 }),
            takeOver: { [weak inboxZero] in inboxZero?.isPlaying = true },
            handBack: { [weak inboxZero] in inboxZero?.isPlaying = false })
        present(game, animated: false)
    }

    /// Where the scene's envelopes and doodles are on the screen now, or `nil` when no scene shows because the Inbox
    /// has mail again.
    private func planeGameStage() -> InboxZeroStage? {
        guard let inboxZero, inboxZero.showing != nil, let stage = inboxZero.stage else { return nil }
        return onScreen(stage)
    }

    /// How many threads the list shows: mail that arrived during the game, since it began on an empty Inbox.
    private func planeGameThreads() -> Int {
        (0..<collectionView.numberOfSections).reduce(0) { $0 + collectionView.numberOfItems(inSection: $1) }
    }

    /// `stage` in the window's coordinates, which are the game's. Converted from the view hosting the scene, which is
    /// right even while the list is pulled and the scene moves with it.
    private func onScreen(_ stage: InboxZeroStage) -> InboxZeroStage? {
        guard let backdrop = collectionView.backgroundView as? InboxZeroBackdrop else { return nil }
        return stage.converted { backdrop.scene.convert($0, to: nil) }
    }
}
