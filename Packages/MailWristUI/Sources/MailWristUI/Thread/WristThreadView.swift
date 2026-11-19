import MailCore
import MailWrist
import SwiftUI

/// A conversation as chat bubbles, newest at the bottom. It asks the iPhone for the messages as it opens, or the
/// account's service when the watch reads the account itself (ADR-023), and says so when neither answers, with Try
/// Again. It opens from the Inbox or from an alert, whose conversation may not be among
/// the Inbox's rows yet.
struct WristThreadView: View {
    let id: ThreadSummary.ID
    let threads: WristThreads
    let inbox: WristInboxModel

    /// What a load depends on: a Try Again, and who serves the conversation.
    private struct Load: Hashable {
        let attempt: Int
        let direct: Bool
    }

    /// Counts Try Again taps: each asks the iPhone again, with its own wait.
    @State private var attempt = 0
    @State private var showsMore = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        content
            .navigationTitle(title)
            // Once the Inbox lists it, which an alert can open before.
            .task(id: row?.id) {
                if let row { inbox.open(row) }
            }
            // Again once the watch reads the account itself, which it can decide only after an alert has opened
            // the conversation at launch.
            .task(id: Load(attempt: attempt, direct: threads.direct.contains(id.accountID))) {
                await threads.load(id)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if row != nil {
                        Button {
                            showsMore = true
                        } label: {
                            Label {
                                Text("More", tableName: "Wrist", bundle: .module, comment: "Opens Pin and Snooze")
                            } icon: {
                                Image(systemName: "ellipsis")
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $showsMore) {
                if let row { WristMoreSheet(row: row, inbox: inbox) { dismiss() } }
            }
    }

    /// The conversation's row as the Inbox shows it now, pinned or not, since the reader may have changed it here;
    /// `nil` while the Inbox doesn't list it.
    private var row: WristRow? {
        guard case .list(let snapshot) = inbox.state else { return nil }
        return snapshot.rows.first { $0.id == id }
    }

    /// Who wrote last, or the subject once the conversation has loaded when the Inbox doesn't list it.
    private var title: String {
        if let row { return row.sender.displayName }
        if case .loaded(let thread) = threads.state(of: id) { return thread.subject }
        return ""
    }

    @ViewBuilder private var content: some View {
        switch threads.state(of: id) {
        case .loading:
            ProgressView()
        case .loaded(let thread):
            WristTranscript(thread: thread, inbox: inbox)
        case .phoneAway:
            ContentUnavailableView {
                Label {
                    Text(
                        "Needs iPhone", tableName: "Wrist", bundle: .module,
                        comment: "Shown when the iPhone didn't send a conversation of an account only it can read")
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
                    Text("Try Again", tableName: "Wrist", bundle: .module, comment: "Tries the same thing again")
                }
            }
        case .failed(let reason):
            ContentUnavailableView {
                Label {
                    Text(
                        "Can’t Load Conversation", tableName: "Wrist", bundle: .module,
                        comment: "Shown when the watch couldn't fetch a conversation from the mail service")
                } icon: {
                    Image(systemName: "wifi.exclamationmark")
                }
            } description: {
                reason.text
            } actions: {
                Button {
                    attempt += 1
                } label: {
                    Text("Try Again", tableName: "Wrist", bundle: .module, comment: "Tries the same thing again")
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
                // Digit by digit, as it's typed, not as one big number.
                .speechSpellsOutCharacters()
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
