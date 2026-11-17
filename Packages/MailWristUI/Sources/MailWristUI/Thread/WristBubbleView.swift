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
            content
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    isMine ? AnyShapeStyle(.tint) : AnyShapeStyle(.fill.secondary), in: .rect(cornerRadius: 14)
                )
                .foregroundStyle(isMine ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .frame(maxWidth: .infinity, alignment: isMine ? .trailing : .leading)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var content: some View {
        switch bubble.content {
        case .words(let words):
            Text(verbatim: words).font(.body)
        case .letter(let subject, let preview):
            VStack(alignment: .leading, spacing: 2) {
                if !subject.isEmpty {
                    Text(verbatim: subject).font(.headline).lineLimit(2)
                }
                Text(verbatim: preview).font(.footnote).lineLimit(4)
                Label {
                    Text("Read on iPhone", tableName: "Wrist", bundle: .module, comment: "A long message's footer")
                } icon: {
                    Image(systemName: "iphone")
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
