#if DEBUG
    import Foundation
    import MailCore
    import MailStore

    /// Launch with `-GoodmailSyntheticCorpus <repo>/TestMail` beside `-GoodmailSyntheticThreads` to file the test-mail
    /// corpus into the synthetic mailbox as whole threads, messages and bodies included, so the reader and compose
    /// can be checked in the simulator without signing in. Each corpus folder is one thread at the top of the first
    /// account's Inbox. Attachments list but don't open: their data would come from a provider.
    enum SyntheticCorpus {
        static var requestedFolder: URL? {
            UserDefaults.standard.string(forKey: "GoodmailSyntheticCorpus").map { URL(filePath: $0) }
        }

        static func file(_ corpus: URL, into database: MailDatabase, account: AccountID, now: Date = .now) throws {
            let folders = try FileManager.default.contentsOfDirectory(at: corpus, includingPropertiesForKeys: nil)
                .filter(\.hasDirectoryPath)
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            for (index, folder) in folders.enumerated() {
                let thread = ThreadSummary.ID(accountID: account, threadID: "corpus-\(folder.lastPathComponent)")
                let raws = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
                    .filter { $0.pathExtension == "eml" }
                    .sorted { $0.lastPathComponent < $1.lastPathComponent }
                    .map { try Data(contentsOf: $0) }
                guard !raws.isEmpty else { continue }
                // Moved as a whole to just before launch, keeping the gaps between its messages.
                let latest = now.addingTimeInterval(-Double(index) * 300)
                let messages = shifted(raws.enumerated().map { message($1, number: $0, in: thread) }, endingAt: latest)
                guard let last = messages.last else { continue }
                try database.upsert([
                    ThreadSummary(
                        id: thread, subject: messages[0].subject, snippet: last.snippet, sender: last.from,
                        date: last.date, isUnread: index.isMultiple(of: 2), messageCount: messages.count,
                        labelIDs: ["INBOX", "CATEGORY_PERSONAL"])
                ])
                try database.save(messages, inThread: thread)
            }
        }

        private static func message(_ raw: Data, number: Int, in thread: ThreadSummary.ID) -> Message {
            let mime = MIMEPart(parsing: raw)
            let (body, attachments) = mime.content()
            func addresses(_ header: String) -> [Contact] { mime.header(header).map(Contact.list(parsing:)) ?? [] }
            return Message(
                id: Message.ID(accountID: thread.accountID, messageID: "\(thread.threadID)-\(number)"),
                threadID: thread.threadID,
                from: addresses("From").first ?? Contact(name: nil, address: ""),
                to: addresses("To"),
                cc: addresses("Cc"),
                bcc: [],
                replyTo: addresses("Reply-To"),
                subject: mime.header("Subject") ?? "",
                date: mime.header("Date").flatMap(dateFormatter.date(from:)) ?? .distantPast,
                snippet: String(
                    (body.plain ?? "").split(whereSeparator: \.isWhitespace).joined(separator: " ").prefix(200)),
                labelIDs: ["INBOX"],
                body: body,
                attachments: attachments,
                internetMessageID: mime.header("Message-ID"),
                references: mime.header("References").map { $0.split(whereSeparator: \.isWhitespace).map(String.init) }
                    ?? [])
        }

        private static func shifted(_ messages: [Message], endingAt latest: Date) -> [Message] {
            guard let newest = messages.map(\.date).max() else { return messages }
            let offset = latest.timeIntervalSince(newest)
            return messages.map { message in
                var message = message
                message.date = message.date == .distantPast ? latest : message.date.addingTimeInterval(offset)
                return message
            }
        }

        private static let dateFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "EEE, d MMM yyyy HH:mm:ss Z"
            return formatter
        }()
    }
#endif
