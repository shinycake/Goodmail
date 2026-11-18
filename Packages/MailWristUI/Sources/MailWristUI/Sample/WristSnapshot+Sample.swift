#if DEBUG
    public import Foundation
    import MailCore
    public import MailWrist

    /// Made-up mail for previews, screenshots and the watch face's placeholder, shown without an iPhone. Plain values
    /// off the main actor, for the widget extension's timeline provider.
    nonisolated extension WristSnapshot {
        public enum SampleLanguage: String, Sendable {
            case english = "en"
            case hebrew = "he"
        }

        public static func sample(_ language: SampleLanguage, now: Date = .now) -> WristSnapshot {
            let personal = AccountID(rawValue: "sample-personal")
            let work = AccountID(rawValue: "sample-work")
            let mail = language == .hebrew ? hebrewMail : englishMail
            return WristSnapshot(
                madeAt: now,
                accounts: [
                    // A Gmail account the watch can read itself (ADR-023) and an iCloud one only the iPhone can.
                    WristAccount(id: personal, address: "maya@example.com", color: .blue, unread: 2, service: .gmail),
                    WristAccount(id: work, address: "maya@example.org", color: .orange, unread: 1, service: .icloud),
                ],
                rows: mail.enumerated().map { index, mail in
                    WristRow(
                        id: ThreadSummary.ID(
                            accountID: index.isMultiple(of: 2) ? personal : work, threadID: "\(index)"),
                        sender: Contact(name: mail.sender, address: "sender\(index)@example.com"),
                        subject: mail.subject, snippet: mail.snippet,
                        date: now.addingTimeInterval(-Double(index * index + 1) * 900), isUnread: index < 3,
                        messageCount: index + 1, isPinned: index == 0, code: nil)
                })
        }

        private typealias SampleMail = (sender: String, subject: String, snippet: String)

        private static let englishMail: [SampleMail] = [
            ("Noa Barak", "Lunch tomorrow?", "Perfect. I'll book a table for four at the new place on Dizengoff."),
            ("Daniel Levi", "Q3 budget review", "Attaching the updated sheet. Can you confirm the totals by Thursday?"),
            ("Lumen Air", "Check-in is open", "Your flight to Lisbon leaves Friday at 08:40 from Terminal 3."),
            ("Tamar Cohen", "Photos from the weekend", "Finally sorted them. The ones from the beach came out great."),
            ("Library", "Your hold is ready", "Pick it up within seven days at the front desk."),
        ]

        private static let hebrewMail: [SampleMail] = [
            ("נועה ברק", "ארוחת צהריים מחר?", "מעולה. אזמין שולחן לארבעה במקום החדש בדיזנגוף."),
            ("דניאל לוי", "סיכום תקציב רבעון 3", "מצרף את הגיליון המעודכן. אפשר לאשר את הסכומים עד יום חמישי?"),
            ("לומן אייר", "הצ׳ק־אין נפתח", "הטיסה שלך לליסבון יוצאת ביום שישי ב‑08:40 מטרמינל 3."),
            ("תמר כהן", "תמונות מסוף השבוע", "סוף סוף סידרתי אותן. אלה מהחוף יצאו נהדר."),
            ("הספרייה", "הספר ששמרת מחכה לך", "אפשר לאסוף אותו בדלפק תוך שבעה ימים."),
        ]
    }
#endif
