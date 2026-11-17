import MailCore
import MailWrist
import SwiftUI

/// The conversations, with how many are unread above them. A tap opens one, a swipe archives, trashes or marks one read, and Undo
/// shows below the list for a few seconds after.
struct WristInboxList: View {
    let snapshot: WristSnapshot
    let model: WristInboxModel
    let threads: WristThreads

    var body: some View {
        List {
            Section {
                ForEach(snapshot.rows) { row in
                    NavigationLink {
                        WristThreadView(row: row, threads: threads, inbox: model)
                    } label: {
                        WristRowView(row: row, color: snapshot.account(row.id.accountID)?.color.color ?? .accentColor)
                    }
                    .swipeActions(edge: .leading) {
                        ReadButton(row: row, model: model)
                    }
                    .swipeActions(edge: .trailing) {
                        RemoveButton(kind: .archive, row: row, model: model)
                        RemoveButton(kind: .trash, row: row, model: model)
                    }
                }
            } header: {
                if snapshot.unread > 0 {
                    Text(
                        "\(snapshot.unread) Unread", tableName: "Wrist", bundle: .module,
                        comment: "Above the Inbox: how many conversations are unread")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let command = model.undoable {
                WristUndoButton(command: command, model: model)
            }
        }
        .sensoryFeedback(.success, trigger: model.undoable)
        .animation(.default, value: snapshot.rows)
    }
}

/// Archives or trashes a conversation.
private struct RemoveButton: View {
    let kind: WristCommand.Kind
    let row: WristRow
    let model: WristInboxModel

    var body: some View {
        Button(role: kind == .trash ? .destructive : nil) {
            model.perform(kind, on: [row])
        } label: {
            if kind == .trash {
                Label {
                    Text("Trash", tableName: "Wrist", bundle: .module, comment: "Swipe action: move to Trash")
                } icon: {
                    Image(systemName: "trash")
                }
            } else {
                Label {
                    Text("Archive", tableName: "Wrist", bundle: .module, comment: "Swipe action: archive")
                } icon: {
                    Image(systemName: "archivebox")
                }
            }
        }
        .tint(kind == .trash ? .red : .indigo)
    }
}

/// Marks a conversation read, or unread when it is read.
private struct ReadButton: View {
    let row: WristRow
    let model: WristInboxModel

    var body: some View {
        Button {
            model.perform(.markRead(row.isUnread), on: [row])
        } label: {
            if row.isUnread {
                Label {
                    Text("Read", tableName: "Wrist", bundle: .module, comment: "Swipe action: mark as read")
                } icon: {
                    Image(systemName: "envelope.open")
                }
            } else {
                Label {
                    Text("Unread", tableName: "Wrist", bundle: .module, comment: "Swipe action: mark as unread")
                } icon: {
                    Image(systemName: "envelope.badge")
                }
            }
        }
        .tint(.blue)
    }
}
