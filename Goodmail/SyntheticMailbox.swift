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
            if seeded { return try model(of: database) }
            let accounts = [
                Account(
                    id: AccountID(rawValue: "synthetic-1"), email: "you@example.com", color: .blue, service: .gmail),
                Account(
                    id: AccountID(rawValue: "synthetic-2"), email: "work@example.com", color: .orange, service: .gmail),
            ]
            for account in accounts { try database.save(account) }
            try database.apply(
                StoreChanges(
                    accountID: accounts[0].id,
                    labels: [
                        MailLabel(id: "Label_1", name: "Receipts", kind: .user, color: "#16a765"),
                        MailLabel(id: "Label_2", name: "Travel", kind: .user, color: "#4a86e8"),
                    ]))
            try database.apply(
                StoreChanges(
                    accountID: accounts[1].id,
                    labels: [MailLabel(id: "Label_3", name: "Clients", kind: .user, color: "#fb4c2f")]))

            let now = Date.now
            var threads: [ThreadSummary] = []
            threads.reserveCapacity(threadCount)
            for index in 0..<threadCount {
                let sender = senders[index % senders.count]
                let isWork = index % 3 == 0
                threads.append(
                    ThreadSummary(
                        id: ThreadSummary.ID(accountID: accounts[isWork ? 1 : 0].id, threadID: "t\(index)"),
                        subject: subjects[index % subjects.count],
                        snippet: snippets[index % snippets.count],
                        sender: Contact(name: sender, address: "sender\(index % senders.count)@example.com"),
                        // Roughly one thread every 20 minutes, so 50k threads span about two years of sections.
                        date: now.addingTimeInterval(-Double(index) * 1_200 - Double(index % 7) * 60),
                        isUnread: index % 4 == 0 || [9, 13].contains(index % 20),
                        messageCount: 1 + index % 5,
                        labelIDs: labels(for: index, isWork: isWork)
                    )
                )
            }
            try database.upsert(threads)
            return try model(of: database)
        }

        private static func model(of database: MailDatabase) throws -> AppModel {
            if let corpus = SyntheticCorpus.requestedFolder {
                try SyntheticCorpus.file(corpus, into: database, account: AccountID(rawValue: "synthetic-1"))
            }
            return try AppModel(database: database)
        }

        /// Mostly Inbox, with some of every other mailbox so each has something to show, and the Inbox spread over
        /// Gmail's categories. Some Inbox threads have no category, as older Gmail mail can. Each account has its own
        /// user labels.
        private static func labels(for index: Int, isWork: Bool) -> Set<String> {
            switch index % 20 {
            case 0, 10: ["INBOX", "CATEGORY_PERSONAL"]
            case 9, 15: ["INBOX", "CATEGORY_PROMOTIONS"]
            case 13: ["INBOX", "CATEGORY_SOCIAL"]
            case 14, 17: ["INBOX", "CATEGORY_UPDATES"]
            case 16: ["INBOX", "CATEGORY_FORUMS"]
            case 1, 11: ["INBOX", "STARRED"]
            case 2, 12: ["SENT"]
            case 3: []
            case 4: ["INBOX", isWork ? "Label_3" : "Label_1"]
            case 5: [isWork ? "Label_3" : "Label_2"]
            case 6: ["TRASH"]
            case 7: ["SPAM"]
            case 8: ["DRAFT"]
            default: ["INBOX"]
            }
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
