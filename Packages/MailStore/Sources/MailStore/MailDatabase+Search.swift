import Foundation
import GRDB
import MailCore

extension MailDatabase {
    /// Threads whose subject, sender, snippet or cached bodies hold each word of `text` (as a word prefix), with
    /// `including`, the provider's matches for it; newest first, Spam and Trash left out as in Gmail's search.
    /// Emits now and after every change.
    public func search(_ text: String, including ids: [ThreadSummary.ID] = [])
        -> AsyncThrowingStream<[ThreadSummary], any Error>
    {
        observe { db in
            guard let query = try Self.searchQuery(text, including: ids) else { return [] }
            return try Self.fetchThreads(db, query: query, limit: Self.searchLimit + ids.count)
        }
    }

    /// Enough local matches to scroll through; the provider's, paged in as the list nears its end, come on top.
    static let searchLimit = 300

    /// `FROM … WHERE …` for `search`, or nil when nothing can match.
    static func searchQuery(_ text: String, including ids: [ThreadSummary.ID]) throws
        -> (sql: String, arguments: StatementArguments)?
    {
        var matches: [String] = []
        var arguments: StatementArguments = []
        if let local = localMatch(SearchQuery(text)) {
            matches.append(local.sql)
            arguments += local.arguments
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

    /// The condition for the threads matching `query` here, or nil when there is nothing to match or the query asks
    /// for something only the provider knows, such as `has:attachment`: then its matches stand alone. A word matches
    /// the thread's subject, sender or snippet, or the body of one of its cached messages.
    static func localMatch(_ query: SearchQuery) -> (sql: String, arguments: StatementArguments)? {
        var patterns: [String] = []
        var conditions: [(sql: String, arguments: StatementArguments)] = []
        for term in query.terms {
            switch (term.name, term.value.lowercased()) {
            case (nil, _):
                guard let pattern = FTS5Pattern(matchingAllPrefixesIn: term.value) else { continue }
                // Each index answers once for the whole list, however many threads there are.
                let sql = """
                    (thread.rowid IN (SELECT rowid FROM threadSearch WHERE threadSearch MATCH ?)
                    OR (thread.accountID, thread.id) IN (
                        SELECT accountID, threadID FROM message
                        WHERE rowid IN (SELECT rowid FROM messageSearch WHERE messageSearch MATCH ?)))
                    """
                conditions.append((sql, [pattern.rawPattern, pattern.rawPattern]))
            case ("is", "unread"): conditions.append(("thread.isUnread", []))
            case ("is", "read"): conditions.append(("NOT thread.isUnread", []))
            case ("is", "starred"):
                let sql = """
                    EXISTS (SELECT 1 FROM threadLabel AS starred
                        WHERE starred.accountID = thread.accountID AND starred.threadID = thread.id
                        AND starred.labelID = ?)
                    """
                conditions.append((sql, [SystemLabel.starred]))
            case ("from", _), ("subject", _):
                guard let pattern = FTS5Pattern(matchingAllPrefixesIn: term.value) else { return nil }
                let columns = term.name == "from" ? "{senderName senderAddress}" : "subject"
                patterns.append("\(columns) : (\(pattern.rawPattern))")
            default: return nil
            }
        }
        if !patterns.isEmpty {
            let sql = "thread.rowid IN (SELECT rowid FROM threadSearch WHERE threadSearch MATCH ?)"
            conditions.insert((sql, [patterns.map { "(\($0))" }.joined(separator: " AND ")]), at: 0)
        }
        guard !conditions.isEmpty else { return nil }
        let arguments = conditions.reduce(into: StatementArguments()) { $0 += $1.arguments }
        return ("(" + conditions.map(\.sql).joined(separator: " AND ") + ")", arguments)
    }
}
