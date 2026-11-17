import MailCore
import MailWrist
import SwiftUI

/// A conversation as chat bubbles, newest at the bottom. It asks the iPhone for the messages as it opens, and says
/// so when the iPhone doesn't answer.
struct WristThreadView: View {
    let row: WristRow
    let threads: WristThreads
    let inbox: WristInboxModel

    /// Counts Try Again taps: each asks the iPhone again, with its own wait.
    @State private var attempt = 0

    var body: some View {
        content
            .navigationTitle(row.sender.displayName)
            .task { inbox.open(row) }
            .task(id: attempt) { await threads.load(row.id) }
    }

    @ViewBuilder private var content: some View {
        switch threads.state(of: row.id) {
        case .loading:
            ProgressView()
        case .loaded(let thread):
            WristTranscript(thread: thread, inbox: inbox)
        case .phoneAway:
            ContentUnavailableView {
                Label {
                    Text(
                        "iPhone Not Reachable", tableName: "Wrist", bundle: .module,
                        comment: "Shown when the iPhone didn't send a conversation")
                } icon: {
                    Image(systemName: "iphone.slash")
                }
            } description: {
                Text(
                    "Bring your iPhone closer to read this conversation.", tableName: "Wrist", bundle: .module,
                    comment: "Shown when the iPhone didn't send a conversation")
            } actions: {
                Button {
                    attempt += 1
                } label: {
                    Text("Try Again", tableName: "Wrist", bundle: .module, comment: "Asks the iPhone again")
                }
            }
        case .gone:
            ContentUnavailableView {
                Label {
                    Text(
                        "Conversation Gone", tableName: "Wrist", bundle: .module,
                        comment: "Shown when the iPhone no longer has the conversation")
                } icon: {
                    Image(systemName: "tray")
                }
            } description: {
                Text(
                    "It was moved or deleted on another device.", tableName: "Wrist", bundle: .module,
                    comment: "Shown when the iPhone no longer has the conversation")
            }
        }
    }
}

/// The bubbles, scrolled to the newest, with a big one-time code above them when the conversation has one, and
/// Reply below them.
private struct WristTranscript: View {
    let thread: WristThread
    let inbox: WristInboxModel

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                if let code = thread.code {
                    WristCodeCard(code: code)
                }
                if thread.earlier > 0 {
                    Text(
                        "\(thread.earlier) earlier messages on iPhone", tableName: "Wrist", bundle: .module,
                        comment: "Above a long conversation: how many older messages the watch leaves out"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                }
                ForEach(thread.bubbles.indices, id: \.self) { index in
                    WristBubbleView(bubble: thread.bubbles[index], showsSender: thread.isGroup)
                }
                NavigationLink {
                    WristReplyView(thread: thread, inbox: inbox)
                } label: {
                    Label {
                        Text(
                            "Reply", tableName: "Wrist", bundle: .module,
                            comment: "Reply: the screen, its field and the button that opens it")
                    } icon: {
                        Image(systemName: "arrowshape.turn.up.left.fill")
                    }
                }
                .padding(.top, 4)
                .wristPrimaryAction()
            }
        }
        .defaultScrollAnchor(.bottom)
        // The watch app has no accent color of its own, and the system's on watchOS is gray, which would make the
        // reader's bubbles hard to tell from everyone else's.
        .tint(.blue)
    }
}

/// A one-time code, big enough to read off the wrist and type in.
private struct WristCodeCard: View {
    let code: String

    var body: some View {
        VStack(spacing: 2) {
            Text("Code", tableName: "Wrist", bundle: .module, comment: "Above a one-time code in a conversation")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(verbatim: code)
                .font(.title2.monospacedDigit().weight(.semibold))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(.tint.opacity(0.2), in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}
