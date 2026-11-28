#if DEBUG
    import Foundation
    import MailCore
    import MailStore

    /// Launch with `-GoodmailSyntheticThreads 50000` for a throwaway mailbox of that many generated threads:
    /// the M1 scroll-performance spike, and screenshots that never show real mail.
    nonisolated enum SyntheticMailbox {
        static var requestedCount: Int? {
            let count = UserDefaults.standard.integer(forKey: "GoodmailSyntheticThreads")
            return count > 0 ? count : nil
        }

        /// Seconds between arrivals, with `-GoodmailSyntheticArrivalEvery`.
        private static var arrivalInterval: Int? {
            let interval = UserDefaults.standard.integer(forKey: "GoodmailSyntheticArrivalEvery")
            return interval > 0 ? interval : nil
        }

        /// The model of a synthetic mailbox of `threadCount` threads, opened and seeded off the main actor.
        @MainActor static func makeModel(threadCount: Int) async throws -> AppModel {
            // Seeded once per size and reused, so launches measure the app rather than the generator. A mailbox
            // taking arrivals starts fresh each launch instead, so earlier arrivals don't pile up at its top.
            let folder = URL.cachesDirectory.appending(
                path: "Synthetic-\(threadCount)\(arrivalInterval == nil ? "" : "-arrivals")")
            if arrivalInterval != nil { try? FileManager.default.removeItem(at: folder) }
            let url = folder.appending(path: "mail.sqlite")
            let seeded = FileManager.default.fileExists(atPath: url.path())
            let database = try await OffMainDatabase.open(url: url)
            let stored = try await database.offMain { database in
                if !seeded { try seed(database, threadCount: threadCount) }
                if let corpus = SyntheticCorpus.requestedFolder {
                    try SyntheticCorpus.file(corpus, into: database, account: AccountID(rawValue: "synthetic-1"))
                }
                return try database.storedAccounts()
            }
            // No push: its accounts aren't real, and asking for alerts would cover the app in UI tests.
            return AppModel(database: database, stored: stored, pushRelay: nil)
        }

        private static func seed(_ database: MailDatabase, threadCount: Int) throws {
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
            try snoozeIfRequested(threads, in: database, now: now)
        }

        /// With `-GoodmailSyntheticSnoozed YES` as well, the two conversations out of every mailbox but All Mail are
        /// snoozed, a day and two days ahead, so Snoozed has rows to read through.
        private static func snoozeIfRequested(_ threads: [ThreadSummary], in database: MailDatabase, now: Date) throws {
            guard UserDefaults.standard.bool(forKey: "GoodmailSyntheticSnoozed") else { return }
            let archived = threads.filter(\.labelIDs.isEmpty).prefix(2)
            var snoozes: [ThreadSummary.ID: SnoozeState?] = [:]
            for (day, thread) in archived.enumerated() {
                snoozes[thread.id] = .asleep(
                    until: now.addingTimeInterval(Double(day + 1) * 86_400), keeper: .thisDevice)
            }
            try database.setSnoozes(snoozes)
        }

        /// With `-GoodmailSyntheticArrivalEvery 2` as well, a new thread lands at the top of the Inbox that many
        /// seconds apart, so the list can be watched taking in mail. The UI tests use it to check that open swipe
        /// buttons stay on their row.
        static func deliverArrivalsIfRequested(to database: OffMainDatabase) {
            guard requestedCount != nil, let interval = arrivalInterval else { return }
            // A debug launch option that runs for the life of the process: nothing awaits or cancels it, and it
            // stops at the first write that fails.
            Task { await deliverArrivals(every: interval, to: database) }
        }

        private static func deliverArrivals(every interval: Int, to database: OffMainDatabase) async {
            for index in 1... {
                do {
                    try await Task.sleep(for: .seconds(interval))
                    let arrival = ThreadSummary(
                        id: ThreadSummary.ID(
                            accountID: AccountID(rawValue: "synthetic-1"), threadID: "arrival-\(index)"),
                        subject: "New arrival \(index)",
                        snippet: "Delivered while the list was open.",
                        sender: Contact(name: "Arrivals", address: "arrivals@example.com"),
                        date: .now, isUnread: true, messageCount: 1, labelIDs: ["INBOX", "CATEGORY_PERSONAL"])
                    try await database.offMain { try $0.upsert([arrival]) }
                } catch {
                    print("Synthetic arrival failed: \(error)")
                    return
                }
            }
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
