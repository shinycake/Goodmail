import Foundation
import MailCore

@testable import MailStore

/// A database the size of a long-kept mailbox: 50,000 threads over three accounts, the third hidden by the Focus.
/// Built once and shared by every test that reads it; nothing writes to it after.
enum Corpus {
    static let threadCount = 50_000
    static let accounts = ["a1", "a2", "a3"].map(AccountID.init(rawValue:))
    /// The accounts the Focus shows.
    static let inFocus = Set(accounts.prefix(2))
    /// A user label on only a few threads, which a plan driven by date would walk the whole table to fill.
    static let sparseLabel = "Label_sparse"
    static let sparseThreads = [7, 12_001, 25_002, 37_500, 49_999]

    static let shared = Result { try build() }

    private static func build() throws -> MailDatabase {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "Corpus-\(UUID().uuidString)")
            .appending(path: "mail.sqlite")
        let database = try MailDatabase(url: url)
        for (index, account) in accounts.enumerated() {
            try database.save(
                Account(id: account, email: "reader\(index)@example.com", color: .teal, service: .gmail))
        }
        try database.upsert((0..<threadCount).map(thread))
        try database.apply(.accounts(inFocus))
        return database
    }

    /// The `index`th thread, older as `index` grows. Pairs share a date, so ties have to be broken.
    static func thread(_ index: Int) -> ThreadSummary {
        ThreadSummary(
            id: ThreadSummary.ID(accountID: accounts[index % accounts.count], threadID: "t\(index)"),
            subject: "Subject \(index)",
            snippet: "Snippet \(index)",
            sender: Contact(name: "Sender \(index % 97)", address: "sender\(index % 97)@example.com"),
            date: Date(timeIntervalSince1970: 1_800_000_000 - Double(index / 2) * 600),
            isUnread: index % 3 == 0,
            messageCount: 1 + index % 4,
            labelIDs: labels(of: index)
        )
    }

    private static func labels(of index: Int) -> Set<String> {
        var labels: Set<String> = []
        switch index % 50 {
        case 0: labels.insert(SystemLabel.spam)
        case 1: labels.insert(SystemLabel.trash)
        case let slot where slot < 22:
            labels.insert(SystemLabel.inbox)
            labels.insert(InboxCategory.allCases[index % InboxCategory.allCases.count].labelID)
        case let slot where slot < 30: labels.insert(SystemLabel.sent)
        default: break
        }
        if index % 20 == 3 { labels.insert(SystemLabel.starred) }
        if sparseThreads.contains(index) { labels.insert(sparseLabel) }
        return labels
    }
}
