import MailWrist
import SwiftUI

/// Says what the last change did and takes it back when tapped. It goes after a few seconds.
struct WristUndoButton: View {
    /// How long Undo stays.
    private static let shown: Duration = .seconds(4)

    let command: WristCommand
    let model: WristInboxModel

    var body: some View {
        Button {
            model.undo()
        } label: {
            Label {
                Text(
                    "\(Self.title(of: command.kind)) · Undo", tableName: "Wrist", bundle: .module,
                    comment: "Below the Inbox after a change: what was done, and the button that takes it back")
            } icon: {
                Image(systemName: "arrow.uturn.backward")
            }
            .font(.footnote.weight(.semibold))
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .task(id: command.id) {
            try? await Task.sleep(for: Self.shown)
            guard !Task.isCancelled else { return }
            model.keep(command)
        }
    }

    private static func title(of kind: WristCommand.Kind) -> String {
        switch kind {
        case .archive:
            String(localized: "Archived", table: "Wrist", bundle: .module, comment: "Undo button: what was done")
        case .trash:
            String(localized: "Moved to Trash", table: "Wrist", bundle: .module, comment: "Undo button: what was done")
        case .markRead(true):
            String(localized: "Marked Read", table: "Wrist", bundle: .module, comment: "Undo button: what was done")
        case .markRead(false):
            String(localized: "Marked Unread", table: "Wrist", bundle: .module, comment: "Undo button: what was done")
        case .pin(true):
            String(localized: "Pinned", table: "Wrist", bundle: .module, comment: "Undo button: what was done")
        case .pin(false):
            String(localized: "Unpinned", table: "Wrist", bundle: .module, comment: "Undo button: what was done")
        case .moveToInbox:
            String(localized: "Moved to Inbox", table: "Wrist", bundle: .module, comment: "Undo button: what was done")
        case .untrash:
            String(localized: "Restored", table: "Wrist", bundle: .module, comment: "Undo button: what was done")
        case .reply:
            String(localized: "Reply Sent", table: "Wrist", bundle: .module, comment: "Undo button: what was done")
        }
    }
}
