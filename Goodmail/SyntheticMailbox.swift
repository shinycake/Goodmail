#if DEBUG
    import Foundation
    import MailCore
    import MailStore

    /// Launch with `-GoodmailSyntheticThreads 50000` for a throwaway mailbox of that many generated threads:
    /// the M1 scroll-performance spike, and screenshots that never show real mail.
    enum SyntheticMailbox {
        static var requestedCount: Int? {
            let count = UserDefaults.standard.integer(forKey: "GoodmailSyntheticThreads")
            return count > 0 ? count : nil
        }

        static func makeModel(threadCount: Int) throws -> AppModel {
            // Seeded once per size and reused, so launches measure the app rather than the generator.
            let url = URL.cachesDirectory.appending(path: "Synthetic-\(threadCount)/mail.sqlite")
            let seeded = FileManager.default.fileExists(atPath: url.path())
            let database = try MailDatabase(url: url)
            if seeded { return try AppModel(database: database) }
            let accounts = [
                Account(id: AccountID(rawValue: "synthetic-1"), email: "you@example.com", color: .blue),
                Account(id: AccountID(rawValue: "synthetic-2"), email: "work@example.com", color: .orange),
            ]
            for account in accounts { try database.save(account) }

            let now = Date.now
            var threads: [ThreadSummary] = []
            threads.reserveCapacity(threadCount)
            for index in 0..<threadCount {
                let sender = senders[index % senders.count]
                threads.append(
                    ThreadSummary(
                        id: ThreadSummary.ID(accountID: accounts[index % 3 == 0 ? 1 : 0].id, threadID: "t\(index)"),
                        subject: subjects[index % subjects.count],
                        snippet: snippets[index % snippets.count],
                        sender: Contact(name: sender, address: "sender\(index % senders.count)@example.com"),
                        // Roughly one thread every 20 minutes, so 50k threads span about two years of sections.
                        date: now.addingTimeInterval(-Double(index) * 1_200 - Double(index % 7) * 60),
                        isUnread: index % 4 == 0,
                        messageCount: 1 + index % 5,
                        labelIDs: ["INBOX"]
                    )
                )
            }
            try database.upsert(threads)
            return try AppModel(database: database)
        }

        private static let senders = [
            "Dana Levi", "יעל כהן", "Noah Peretz", "Maya Friedman", "GitHub", "אבי מזרחי", "Apple", "Tamar Shapiro",
        ]
        private static let subjects = [
            "Lunch tomorrow?", "סיכום פגישה", "Your receipt from Apple", "Weekend plans", "[goodmail] CI passed",
            "Quarterly report draft — please review by Thursday", "תזכורת: תור לרופא", "Photos from the trip",
        ]
        private static let snippets = [
            "Sure — let's do 12:30 at the usual place. I'll book a table for four.",
            "שלום, מצורף הסיכום של הפגישה מהיום. אשמח להערות עד סוף השבוע.",
            "Thanks for your purchase. This is a receipt for your records; no action is needed.",
            "Are you around on Saturday? We were thinking of a short hike and then brunch.",
        ]
    }
#endif
