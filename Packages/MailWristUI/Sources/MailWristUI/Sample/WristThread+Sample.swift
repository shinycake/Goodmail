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

    /// The sample Inbox's first conversation, opened, for screenshots.
    public struct WristSampleThreadScreen: View {
        let inbox: WristInboxModel
        let threads: WristThreads

        public init(inbox: WristInboxModel, threads: WristThreads) {
            self.inbox = inbox
            self.threads = threads
        }

        public var body: some View {
            NavigationStack {
                if case .list(let snapshot) = inbox.state, let row = snapshot.rows.first {
                    WristThreadView(row: row, threads: threads, inbox: inbox)
                }
            }
        }
    }
#endif
