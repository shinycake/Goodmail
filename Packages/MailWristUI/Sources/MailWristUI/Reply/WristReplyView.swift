import MailCore
import MailWrist
import SwiftUI

/// Answers a conversation from the wrist: dictate or scribble a reply, or pick a quick one. After Send it waits a
/// few seconds with Undo, then goes back to the conversation while the iPhone sends it.
struct WristReplyView: View {
    let thread: WristThread
    @State private var reply: WristReplyModel
    /// The words being written, kept when Undo hands them back.
    @State private var draft = ""
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    init(thread: WristThread, inbox: WristInboxModel) {
        self.thread = thread
        let id = thread.id
        _reply = State(initialValue: WristReplyModel { text in inbox.reply(text, in: id) })
    }

    var body: some View {
        content
            .navigationTitle(
                Text(
                    "Reply", tableName: "Wrist", bundle: .module,
                    comment: "Reply: the screen, its field and the button that opens it")
            )
            // The held reply goes once its moment is over, or at once when the reader leaves the screen, which
            // cancels the wait. Undo ends the hold, which cancels it too.
            .task(id: reply.held) {
                if let held = reply.held { await reply.release(held) }
            }
            // The app can be suspended once it is in the background, before the moment is over: the reply goes then.
            // Inactive, as under a banner or with the wrist down in Always On, it keeps waiting, so Undo stays.
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { reply.releaseNow() }
            }
            .onChange(of: reply.state) { _, state in
                if case .sent = state { dismiss() }
            }
            .sensoryFeedback(.success, trigger: reply.state) { _, state in
                if case .sent = state { true } else { false }
            }
    }

    @ViewBuilder private var content: some View {
        switch reply.state {
        case .writing:
            WristReplyChoices(answers: WristQuickReplies.answers(for: thread), draft: $draft) { text in
                reply.send(text)
            }
        case .holding(let held):
            WristReplyHold(text: held.text) {
                if let text = reply.undo() { draft = text }
            }
        case .sent:
            Image(systemName: "checkmark.circle.fill")
                .font(.largeTitle)
                .foregroundStyle(.green)
                .accessibilityLabel(
                    Text("Reply Sent", tableName: "Wrist", bundle: .module, comment: "Undo button: what was done"))
        }
    }
}

/// A field to dictate or scribble into, and the quick replies below it.
private struct WristReplyChoices: View {
    let answers: [String]
    @Binding var draft: String
    let send: (String) -> Void

    var body: some View {
        List {
            TextField(
                text: $draft,
                prompt: Text(
                    "Dictate or Scribble", tableName: "Wrist", bundle: .module,
                    comment: "The reply field's placeholder")
            ) {
                Text(
                    "Reply", tableName: "Wrist", bundle: .module,
                    comment: "Reply: the screen, its field and the button that opens it")
            }
            .onSubmit { send(draft) }
            Section {
                ForEach(answers, id: \.self) { answer in
                    Button {
                        send(answer)
                    } label: {
                        Text(verbatim: answer)
                    }
                }
            }
        }
    }
}

/// The reply about to go, with Undo, for the few seconds before it does.
private struct WristReplyHold: View {
    let text: String
    let undo: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Text(verbatim: text)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.blue, in: .rect(cornerRadius: 14))
                .foregroundStyle(.white)
                .lineLimit(4)
            Text("Sending…", tableName: "Wrist", bundle: .module, comment: "Shown while a reply waits for Undo")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button(action: undo) {
                Text("Undo", tableName: "Wrist", bundle: .module, comment: "Takes back a reply before it goes")
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
        }
    }
}
