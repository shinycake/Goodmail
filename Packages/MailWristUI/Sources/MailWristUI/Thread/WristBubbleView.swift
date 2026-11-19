import MailCore
import MailWrist
import SwiftUI

/// One message as a bubble: the reader's own on the trailing side in the accent color, everyone else's on the
/// leading side, with the time above it after a pause.
struct WristBubbleView: View {
    let bubble: WristBubble
    /// Names the sender above their bubble, for a conversation with more than one other person.
    let showsSender: Bool

    private var isMine: Bool { bubble.side == .mine }

    var body: some View {
        VStack(alignment: isMine ? .trailing : .leading, spacing: 2) {
            if let time = bubble.time {
                Text(time, format: .relative(presentation: .named))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
            if showsSender, !isMine {
                Text(bubble.sender).font(.caption2).foregroundStyle(.secondary).padding(.horizontal, 8)
            }
            if case .letter(let letter) = bubble.content {
                // A letter opens on a screen of its own, with every word.
                NavigationLink {
                    WristLetterView(letter: letter, sender: bubble.sender)
                } label: {
                    shaped
                }
                .buttonStyle(.plain)
            } else {
                shaped
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel { label in
            if let speaker {
                speaker
            }
            label
        }
    }

    /// Who wrote the bubble, for VoiceOver, where the side it sits on and its color don't say: the reader, or the
    /// other person when their name isn't shown above it.
    private var speaker: Text? {
        if isMine {
            Text("You", tableName: "Wrist", bundle: .module, comment: "VoiceOver: before the reader's own message")
        } else if showsSender {
            nil
        } else {
            Text(verbatim: bubble.sender)
        }
    }

    /// The content in the bubble's shape and color, on its side.
    private var shaped: some View {
        content
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                isMine ? AnyShapeStyle(.tint) : AnyShapeStyle(.fill.secondary), in: .rect(cornerRadius: 14)
            )
            .foregroundStyle(isMine ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .frame(maxWidth: .infinity, alignment: isMine ? .trailing : .leading)
    }

    @ViewBuilder private var content: some View {
        switch bubble.content {
        case .words(let words):
            // Links take the words' own color in the reader's tinted bubble, where the tint would vanish.
            Text(AttributedString(words)).font(.body).tint(isMine ? .white : nil)
        case .letter(let letter):
            VStack(alignment: .leading, spacing: 2) {
                if !letter.subject.isEmpty {
                    Text(verbatim: letter.subject).font(.headline).lineLimit(2)
                }
                Text(AttributedString(letter.preview)).font(.footnote).lineLimit(4).tint(isMine ? .white : nil)
                Label {
                    Text(
                        "Read Message", tableName: "Wrist", bundle: .module,
                        comment: "A long message's footer, which opens it in full")
                } icon: {
                    Image(systemName: "chevron.forward")
                }
                .font(.caption2)
                .opacity(0.8)
            }
        case .attachment(let name):
            Label {
                Text(verbatim: name).lineLimit(1)
            } icon: {
                Image(systemName: "paperclip")
            }
            .font(.footnote)
        }
    }
}
