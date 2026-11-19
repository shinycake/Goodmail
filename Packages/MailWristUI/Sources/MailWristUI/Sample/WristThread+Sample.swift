#if DEBUG
    public import Foundation
    import MailCore
    public import MailWrist

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
                                content: .words(StyledText(row.snippet)))
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
            let chat = lines.enumerated().map { index, line in
                WristBubble(
                    side: line.0, sender: sender, time: index == 0 ? now.addingTimeInterval(-3600) : nil,
                    content: .words(StyledText(line.1)))
            }
            return chat + [WristBubble(side: .theirs, sender: sender, time: nil, content: .letter(booking(language)))]
        }

        /// A forwarded booking, long enough to open on its own screen.
        private static func booking(_ language: WristSnapshot.SampleLanguage) -> WristLetter {
            var words = StyledText()
            if language == .hebrew {
                words.append("ההזמנה שלך אושרה", style: .bold)
                words.append("\nיום שישי, 13:00 · 4 סועדים\nדיזנגוף 99, תל אביב\n\n")
                words.append("לשינוי או ביטול ההזמנה, ")
                words.append("לחצו כאן", link: URL(string: "https://example.com/booking"))
                words.append(" עד שעתיים לפני.\n\nהשולחן נשמר ל-15 דקות. מחכים לכם!")
                return WristLetter(subject: "הזמנת שולחן", words: words, extent: .whole)
            }
            words.append("Your table is booked", style: .bold)
            words.append("\nFriday, 1:00 PM · Party of 4\n99 Dizengoff St, Tel Aviv\n\n")
            words.append("To change or cancel, ")
            words.append("manage your booking", link: URL(string: "https://example.com/booking"))
            words.append(" up to two hours before.\n\nWe hold tables for 15 minutes. See you soon!")
            return WristLetter(subject: "Table for 4 confirmed", words: words, extent: .whole)
        }
    }
#endif
