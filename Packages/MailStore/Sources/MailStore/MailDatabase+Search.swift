import Foundation
import GRDB
import MailCore

extension MailDatabase {
    /// Threads whose subject, sender or snippet hold every word of `text` (each as a word prefix), together with
    /// `including`, the provider's matches for it; newest first, Spam and Trash left out as in Gmail's search.
    /// Emits now and after every change.
    public func search(_ text: String, including ids: [ThreadSummary.ID] = [])
        -> AsyncThrowingStream<[ThreadSummary], any Error>
    {
        observe { db in
            guard let query = try Self.searchQuery(text, including: ids) else { return [] }
            return try Self.fetchThreads(db, query: query, limit: Self.searchLimit)
        }
    }

    /// Enough to scroll through; the provider's search goes further.
    static let searchLimit = 300

    /// `FROM … WHERE …` for `search`, or nil when nothing can match.
    static func searchQuery(_ text: String, including ids: [ThreadSummary.ID]) throws
        -> (sql: String, arguments: StatementArguments)?
    {
        var matches: [String] = []
        var arguments: StatementArguments = []
        if let pattern = FTS5Pattern(matchingAllPrefixesIn: localTerms(text)) {
            matches.append("thread.rowid IN (SELECT rowid FROM threadSearch WHERE threadSearch MATCH ?)")
            arguments += [pattern]
        }
        if !ids.isEmpty {
            // Thread IDs are only unique per account, so match the pair.
            matches.append("thread.accountID || char(31) || thread.id IN (SELECT value FROM json_each(?))")
            let keys = ids.map { $0.accountID.rawValue + "\u{1F}" + $0.threadID }
            arguments += [String(decoding: try JSONEncoder().encode(keys), as: UTF8.self)]
        }
        guard !matches.isEmpty else { return nil }
        let sql = """
            FROM thread
            WHERE (\(matches.joined(separator: " OR ")))
            AND NOT EXISTS (
                SELECT 1 FROM threadLabel AS excluded
                WHERE excluded.accountID = thread.accountID AND excluded.threadID = thread.id
                AND excluded.labelID IN (?, ?))
            """
        return (sql, arguments + [SystemLabel.spam, SystemLabel.trash])
    }

    /// The words to look for locally: Gmail operators such as `from:` are left to the provider, keeping their value.
    static func localTerms(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace)
            .map { word in
                guard let colon = word.firstIndex(of: ":"), word[..<colon].allSatisfy(\.isLetter) else {
                    return word
                }
                return word[word.index(after: colon)...]
            }
            .joined(separator: " ")
    }
}
