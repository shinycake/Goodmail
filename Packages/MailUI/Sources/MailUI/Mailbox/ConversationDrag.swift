import MailCore
import UIKit

/// What a dragged row stands for when it is dropped inside the app, as on a mailbox in the sidebar: the conversation,
/// and the mailbox it was dragged from. Every item of a drag carries one, whatever else the item holds for other apps.
nonisolated struct DraggedThread: Sendable {
    let id: ThreadSummary.ID
    let mailbox: Mailbox
}

/// What a drag out of the list carries beyond the conversations themselves. Decided here, once, from how the window is
/// driven.
enum ConversationCarry {
    /// Touch: the new window the row opens when dropped outside the window, as Apple Mail on iPad does.
    case window((ThreadSummary.ID) -> WindowState)
    /// Pointer: one `.eml` file for each message, for Finder and other apps. A new window comes from a double-click.
    case files(ConversationFiles)

    /// `nil` where nothing can be dragged: a touch device without windows, a desktop list with no way to read mail.
    init?(
        style: InteractionStyle, window: @escaping (ThreadSummary.ID) -> WindowState,
        sources: ConversationSources?, supportsWindows: Bool
    ) {
        switch style {
        case .touch:
            guard supportsWindows else { return nil }
            self = .window(window)
        case .desktop:
            guard let sources else { return nil }
            self = .files(ConversationFiles(sources))
        }
    }
}

/// Lets conversations be dragged out of the list: onto a mailbox in the sidebar to move them, and out of the window
/// as `ConversationCarry` says.
final class ConversationDrag: NSObject, UICollectionViewDragDelegate {
    /// The conversations a drag begun at a row takes: the row's, or the whole pick when the row is in it. None where a
    /// row can't be dragged now, as while selecting several.
    private let threads: (IndexPath) -> [ThreadSummary]
    private let carry: ConversationCarry
    /// The mailbox the list shows, which the drop's move leaves.
    private let mailbox: Mailbox
    /// Called as a drag begins, so the list can close what it shows over its rows.
    private let willBegin: () -> Void

    init(
        threads: @escaping (IndexPath) -> [ThreadSummary], carry: ConversationCarry, mailbox: Mailbox,
        willBegin: @escaping () -> Void
    ) {
        self.threads = threads
        self.carry = carry
        self.mailbox = mailbox
        self.willBegin = willBegin
    }

    func collectionView(
        _ collectionView: UICollectionView, itemsForBeginning session: any UIDragSession, at indexPath: IndexPath
    ) -> [UIDragItem] {
        let dragged = threads(indexPath)
        guard !dragged.isEmpty else { return [] }
        switch carry {
        case .window(let window):
            guard let thread = dragged.first, let activity = window(thread.id).activity else { return [] }
            willBegin()
            let provider = NSItemProvider()
            provider.registerObject(activity, visibility: .all)
            let item = UIDragItem(itemProvider: provider)
            item.localObject = DraggedThread(id: thread.id, mailbox: mailbox)
            return [item]
        case .files(let files):
            willBegin()
            return dragged.flatMap { files.items(for: $0, carrying: DraggedThread(id: $0.id, mailbox: mailbox)) }
        }
    }
}
