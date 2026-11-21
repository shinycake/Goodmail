import Foundation
import GRDB
import MailCore

/// Which stored conversations meet smart mailboxes' conditions (ADR-039). A conversation is in a box when its list
/// row meets the condition, or one of its messages cached on the device does, as a conversation from a VIP stays in
/// VIPs after the reader answers it. Like All Mail and search, a box leaves out Spam and Trash and the accounts the
/// Focus hides. Each read decodes the cached messages without their bodies, which the store keeps as plain text
/// beside them for what a condition asks of a body.
struct SmartMatch {
    private let db: Database
    private let lookup: FactsLookup
    private let context: MailCondition.Context

    init(_ db: Database, mailboxNames: [String: String], context: MailCondition.Context) throws {
        self.db = db
        lookup = try FactsLookup(db, mailboxNames: mailboxNames)
        self.context = context
    }

    /// Each condition's conversations, newest first; `unreadOnly` reads the unread ones alone, for the counts.
    func threads(meeting conditions: [SmartMailbox.ID: MailCondition], unreadOnly: Bool) throws
        -> [SmartMailbox.ID: [ThreadSummary]]
    {
        guard !conditions.isEmpty else { return [:] }
        var query = MailDatabase.threadQuery(in: .allMail)
        if unreadOnly { query.sql += " AND thread.isUnread" }
        let bounds = Self.loosestBounds(of: conditions.values, now: context.now)
        if let from = bounds.from {
            query.sql += " AND thread.date >= ?"
            query.arguments += [from]
        }
        if let to = bounds.to {
            query.sql += " AND thread.date <= ?"
            query.arguments += [to]
        }
        let threads = try MailDatabase.fetchThreads(db, query: query)
        var matched: [SmartMailbox.ID: Set<ThreadSummary.ID>] = conditions.mapValues { _ in [] }
        var unsettled: Set<ThreadSummary.ID> = []
        for thread in threads {
            guard let facts = lookup.facts(of: thread) else { continue }
            for (box, condition) in conditions where condition.matches(facts, in: context) {
                matched[box, default: []].insert(thread.id)
            }
            if matched.values.contains(where: { !$0.contains(thread.id) }) { unsettled.insert(thread.id) }
        }
        let byID = Dictionary(uniqueKeysWithValues: threads.map { ($0.id, $0) })
        try forEachCachedMessage(of: unsettled, threads: byID) { facts in
            for (box, condition) in conditions
            where !matched[box, default: []].contains(facts.envelope.thread) && condition.matches(facts, in: context) {
                matched[box, default: []].insert(facts.envelope.thread)
            }
        }
        return matched.mapValues { ids in threads.filter { ids.contains($0.id) } }
    }

    /// Calls `body` with each cached message of `ids`. The body is left out of the decoding: a condition reads the
    /// plain text the store keeps beside it.
    private func forEachCachedMessage(
        of ids: Set<ThreadSummary.ID>, threads: [ThreadSummary.ID: ThreadSummary], _ body: (MailFacts) -> Void
    ) throws {
        guard !ids.isEmpty else { return }
        let keys = ids.map { $0.accountID.rawValue + "\u{1F}" + $0.threadID }
        let rows = try Row.fetchCursor(
            db,
            sql: """
                SELECT json_set(content, '$.body', json('{}')) AS content, COALESCE(bodyText, '') AS bodyText,
                    accountID, threadID
                FROM message WHERE accountID || char(31) || threadID IN (SELECT value FROM json_each(?))
                """,
            arguments: [String(decoding: try JSONEncoder().encode(keys), as: UTF8.self)])
        let decoder = JSONDecoder()
        while let row = try rows.next() {
            let id = ThreadSummary.ID(accountID: AccountID(rawValue: row["accountID"]), threadID: row["threadID"])
            // A message this build can't decode, or whose account is gone, says nothing.
            guard let thread = threads[id], let account = lookup.accounts[id.accountID],
                let message = try? decoder.decode(Message.self, from: Data((row["content"] as String).utf8))
            else { continue }
            body(
                MailFacts(
                    message: message, bodyText: row["bodyText"], thread: thread, account: account,
                    local: lookup.local(of: id), labelNames: lookup.names(in: account.id)))
        }
    }

    /// The widest dates any of the conditions allows, so one read serves them all. An end any condition leaves open
    /// stays open.
    static func loosestBounds(of conditions: some Collection<MailCondition>, now: Date) -> (from: Date?, to: Date?) {
        let bounds = conditions.map { $0.dateBounds(now: now) }
        let froms = bounds.map(\.from)
        let tos = bounds.map(\.to)
        return (
            froms.contains(nil) ? nil : froms.compactMap(\.self).min(),
            tos.contains(nil) ? nil : tos.compactMap(\.self).max()
        )
    }
}
