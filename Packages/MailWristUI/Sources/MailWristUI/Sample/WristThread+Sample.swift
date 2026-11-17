#if DEBUG
    public import Foundation
    import MailCore
    public import MailWrist
    public import SwiftUI

    extension WristThread {
        /// A made-up conversation for each row of `snapshot`, which `WristSnapshot.sample` made in `language`. The
        /// first is a back-and-forth; the others are the row's one message.
        public static func samples(
            for snapshot: WristSnapshot, _ language: WristSnapshot.SampleLanguage, now: Date = .now
        ) -> [WristThread] {
            snapshot.rows.enumerated().map { index, row in
                let bubbles: [WristBubble] =
                    if index == 0 {
                        chat(language, with: row.sender.displayName, now: now)
                    } else {
                        [
                            WristBubble(
                                side: .theirs, sender: row.sender.displayName, time: row.date,
                                content: .words(row.snippet))
                        ]
                    }
                return WristThread(
                    id: row.id, subject: row.subject, bubbles: bubbles, earlier: 0, isGroup: false, code: nil)
            }
        }

        private static func chat(_ language: WristSnapshot.SampleLanguage, with sender: String, now: Date)
            -> [WristBubble]
        {
            let lines =
                language == .hebrew
                ? [
                    (WristBubble.Side.theirs, "היי! פנויה לארוחת צהריים מחר?"),
                    (.mine, "כן! איפה חשבת?"),
                    (.theirs, "המקום החדש בדיזנגוף. שמעתי שהוא מעולה"),
                    (.mine, "סגור. 13:00?"),
                    (.theirs, "מעולה. אזמין שולחן לארבעה במקום החדש בדיזנגוף."),
                ]
                : [
                    (WristBubble.Side.theirs, "Hey! Free for lunch tomorrow?"),
                    (.mine, "Yes! Where were you thinking?"),
                    (.theirs, "The new place on Dizengoff. I hear it's great"),
                    (.mine, "Deal. 1 PM?"),
                    (.theirs, "Perfect. I'll book a table for four at the new place on Dizengoff."),
                ]
            return lines.enumerated().map { index, line in
                WristBubble(
                    side: line.0, sender: sender, time: index == 0 ? now.addingTimeInterval(-3600) : nil,
                    content: .words(line.1))
            }
        }
    }

    /// The sample Inbox with its first conversation pushed over it, for screenshots. Closing the conversation, or
    /// snoozing it, goes back to the Inbox as it would after a tap.
    public struct WristSampleThreadScreen: View {
        let inbox: WristInboxModel
        let threads: WristThreads
        /// The first conversation, kept as it was at launch so the pushed screen doesn't follow the Inbox's new
        /// first row after a snooze.
        @State private var opened: WristRow?

        public init(inbox: WristInboxModel, threads: WristThreads) {
            self.inbox = inbox
            self.threads = threads
            if case .list(let snapshot) = inbox.state { _opened = State(initialValue: snapshot.rows.first) }
        }

        public var body: some View {
            NavigationStack {
                if case .list(let snapshot) = inbox.state {
                    WristInboxList(snapshot: snapshot, model: inbox, threads: threads)
                        .navigationTitle(
                            Text("Inbox", tableName: "Wrist", bundle: .module, comment: "The Inbox screen's title")
                        )
                        .navigationDestination(isPresented: isOpen) {
                            if let opened {
                                WristThreadView(row: opened, threads: threads, inbox: inbox)
                            }
                        }
                }
            }
        }

        private var isOpen: Binding<Bool> {
            Binding {
                opened != nil
            } set: {
                if !$0 { opened = nil }
            }
        }
    }
#endif
