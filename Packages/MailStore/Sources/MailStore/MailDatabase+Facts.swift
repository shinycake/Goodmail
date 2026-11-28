import Foundation
import GRDB
public import MailCore

/// Mail as filters and rules see it (`MailFacts`): Shortcuts' Find actions and the rules that run as mail arrives.
extension MailDatabase {
    /// Stops a filter that matches nearly everything before it reads the whole cache.
    public static let factsMatchLimit = 2000

    /// The cached messages that meet `condition`, newest first, up to `factsMatchLimit`. Only the dates the
    /// condition allows are read (`MailCondition.dateBounds`). `mailboxNames` names the standard mailboxes by label
    /// ID, as the mailbox list does; user labels carry their own names.
    public func messageFacts(
        matching condition: MailCondition, in context: MailCondition.Context, mailboxNames: [String: String]
    ) throws -> [MailFacts] {
        let bounds = condition.dateBounds(now: context.now)
        var filters: [String] = []
        var arguments: StatementArguments = []
        if let from = bounds.from {
            filters.append("message.date >= ?")
            arguments += [from]
        }
        if let to = bounds.to {
            filters.append("message.date <= ?")
            arguments += [to]
        }
        return try pool.read { db in
            let lookup = try FactsLookup(db, mailboxNames: mailboxNames)
            return try lookup.messages(
                db, where: filters.isEmpty ? "1" : filters.joined(separator: " AND "), arguments: arguments
            ) { condition.matches($0, in: context) }
        }
    }

    /// The cached messages of the threads, newest first, as Shortcuts asks for the ones it holds by identifier.
    public func messageFacts(inThreads ids: [ThreadSummary.ID], mailboxNames: [String: String]) throws -> [MailFacts] {
        guard !ids.isEmpty else { return [] }
        let keys = ids.map { $0.accountID.rawValue + "\u{1F}" + $0.threadID }
        let json = String(decoding: try JSONEncoder().encode(keys), as: UTF8.self)
        return try pool.read { db in
            try FactsLookup(db, mailboxNames: mailboxNames).messages(
                db, where: "message.accountID || char(31) || message.threadID IN (SELECT value FROM json_each(?))",
                arguments: [json]
            ) { _ in true }
        }
    }

    /// The stored threads among `ids`, newest first, each as its list row shows it.
    public func threadFacts(_ ids: [ThreadSummary.ID], mailboxNames: [String: String]) throws -> [MailFacts] {
        let threads = try threads(ids)
        return try pool.read { db in
            let lookup = try FactsLookup(db, mailboxNames: mailboxNames)
            return threads.compactMap(lookup.facts(of:))
        }
    }

    /// The stored threads that meet `condition`, newest first, up to `factsMatchLimit`, each as its list row shows
    /// it: what only a cached message knows is unknown, so a condition on it doesn't hold.
    public func threadFacts(
        matching condition: MailCondition, in context: MailCondition.Context, mailboxNames: [String: String]
    ) throws -> [MailFacts] {
        let bounds = condition.dateBounds(now: context.now)
        var sql = "FROM thread WHERE 1"
        var arguments: StatementArguments = []
        if let from = bounds.from {
            sql += " AND thread.date >= ?"
            arguments += [from]
        }
        if let to = bounds.to {
            sql += " AND thread.date <= ?"
            arguments += [to]
        }
        return try pool.read { db in
            let lookup = try FactsLookup(db, mailboxNames: mailboxNames)
            var matches: [MailFacts] = []
            for thread in try Self.fetchThreads(
                db, query: ThreadSelection(sql: sql, arguments: arguments, order: .thread))
            {
                guard let facts = lookup.facts(of: thread), condition.matches(facts, in: context) else { continue }
                matches.append(facts)
                if matches.count == Self.factsMatchLimit { break }
            }
            return matches
        }
    }
}

/// What a read of facts looks up for every mail it builds: the accounts, the label names, pins and snoozes. Each
/// is a small table, read once.
struct FactsLookup {
    let accounts: [AccountID: Account]
    let labelNames: [AccountID: [String: String]]
    let pins: Set<ThreadSummary.ID>
    let snoozes: [ThreadSummary.ID: SnoozeState]
    /// The standard mailboxes' names, for an account with no labels of its own.
    let mailboxNames: [String: String]

    init(_ db: Database, mailboxNames: [String: String]) throws {
        let accounts = try AccountRecord.fetchAll(db).compactMap(\.account)
        self.accounts = Dictionary(accounts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var names: [AccountID: [String: String]] = [:]
        for row in try Row.fetchAll(db, sql: "SELECT accountID, id, name FROM label WHERE kind = 'user'") {
            names[AccountID(rawValue: row["accountID"]), default: mailboxNames][row["id"]] = row["name"] as String
        }
        labelNames = names
        pins = Set(
            try Row.fetchAll(db, sql: "SELECT accountID, threadID FROM pin").map { row in
                ThreadSummary.ID(accountID: AccountID(rawValue: row["accountID"]), threadID: row["threadID"])
            })
        var snoozes: [ThreadSummary.ID: SnoozeState] = [:]
        for row in try Row.fetchAll(db, sql: "SELECT accountID, threadID, wakeAt, wokeAt, keeper FROM snooze") {
            let id = ThreadSummary.ID(accountID: AccountID(rawValue: row["accountID"]), threadID: row["threadID"])
            snoozes[id] = MailDatabase.state(row)
        }
        self.snoozes = snoozes
        self.mailboxNames = mailboxNames
    }

    func local(of thread: ThreadSummary.ID) -> MailFacts.Local {
        MailFacts.Local(isPinned: pins.contains(thread), snooze: snoozes[thread])
    }

    func names(in account: AccountID) -> [String: String] {
        labelNames[account] ?? mailboxNames
    }

    /// The thread as its list row shows it, or `nil` when its account is gone.
    func facts(of thread: ThreadSummary) -> MailFacts? {
        guard let account = accounts[thread.id.accountID] else { return nil }
        return MailFacts(
            thread: thread, account: account, local: local(of: thread.id), labelNames: names(in: account.id))
    }

    /// The cached messages `filter` selects that `keep` takes, newest first, up to `factsMatchLimit`. A message this
    /// build can't decode is skipped.
    func messages(
        _ db: Database, where filter: String, arguments: StatementArguments, keep: (MailFacts) -> Bool
    ) throws -> [MailFacts] {
        let rows = try Row.fetchCursor(
            db,
            sql: """
                SELECT message.content, COALESCE(message.bodyText, '') AS bodyText, message.accountID, message.threadID
                FROM message WHERE \(filter) ORDER BY message.date DESC
                """,
            arguments: arguments)
        let decoder = JSONDecoder()
        var threads: [ThreadSummary.ID: ThreadSummary] = [:]
        var matches: [MailFacts] = []
        while let row = try rows.next() {
            let id = ThreadSummary.ID(accountID: AccountID(rawValue: row["accountID"]), threadID: row["threadID"])
            guard let account = accounts[id.accountID],
                let message = try? decoder.decode(Message.self, from: Data((row["content"] as String).utf8)),
                let thread = try threads[id] ?? MailDatabase.fetchThreads(db, query: Self.one(id)).first
            else { continue }
            threads[id] = thread
            let facts = MailFacts(
                message: message, bodyText: row["bodyText"], thread: thread, account: account, local: local(of: id),
                labelNames: names(in: account.id))
            guard keep(facts) else { continue }
            matches.append(facts)
            if matches.count == MailDatabase.factsMatchLimit { break }
        }
        return matches
    }

    private static func one(_ id: ThreadSummary.ID) -> ThreadSelection {
        ThreadSelection(
            sql: "FROM thread WHERE thread.accountID = ? AND thread.id = ?",
            arguments: [id.accountID.rawValue, id.threadID], order: .thread)
    }
}
