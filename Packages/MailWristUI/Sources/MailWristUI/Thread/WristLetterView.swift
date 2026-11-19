import MailCore
import MailWrist
import SwiftUI

/// A long or laid-out message in full: its subject, then its words a line at a time, so a long newsletter lays out only
/// as far as it scrolls. One the iPhone had to cut short says the rest reads there.
struct WristLetterView: View {
    let letter: WristLetter
    let sender: String

    /// A line and its place in the letter, which never changes, since the letter doesn't.
    private struct Line: Identifiable {
        let id: Int
        let words: StyledText
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                if !letter.subject.isEmpty {
                    Text(verbatim: letter.subject).font(.headline).padding(.bottom, 8)
                }
                ForEach(lines) { line in
                    // A blank line spaces the blocks around it, as it does in the mail.
                    Text(AttributedString(line.words)).font(.body).frame(minHeight: line.words.isEmpty ? 10 : nil)
                }
                if letter.extent == .start {
                    Label {
                        Text(
                            "The rest of this message is on your iPhone.", tableName: "Wrist", bundle: .module,
                            comment: "Below a message the watch could get only the start of")
                    } icon: {
                        Image(systemName: "iphone")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(Text(verbatim: sender))
        // Links in the system's gray tint would hardly stand out from the words.
        .tint(.blue)
    }

    private var lines: [Line] {
        letter.lines.enumerated().map { Line(id: $0.offset, words: $0.element) }
    }
}
