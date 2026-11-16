import Foundation
import MailCore
import Synchronization

@testable import MailIntents

/// A host with fixed mail. A value, so each test builds its own; the actions performed through it land in
/// `performed`, shared by its copies.
struct FakeHost: MailIntentsHost {
    var accountList: [Account] = []
    var labels: [AccountID: [NamedMailbox]] = [:]
    var stored: [ThreadSummary] = []
    var cached: [ThreadSummary.ID: [Message]] = [:]
    /// What leaving a list comes to.
    var unsubscribing: ListUnsubscriber.Outcome = .done
    let performed = Performed()

    func accounts() throws -> [Account] { accountList }

    func mailboxes(of account: AccountID) throws -> [NamedMailbox] {
        Mailbox.standard.map { NamedMailbox(mailbox: $0, name: $0.labelID ?? "All Mail") } + (labels[account] ?? [])
    }

    func threads(_ ids: [ThreadSummary.ID]) throws -> [ThreadSummary] {
        stored.filter { ids.contains($0.id) }
    }

    func threads(in mailbox: Mailbox, limit: Int) throws -> [ThreadSummary] {
        Array(stored.filter(mailbox.contains).prefix(limit))
    }

    func threads(matching text: String, limit: Int) throws -> [ThreadSummary] {
        Array(stored.filter { $0.subject.localizedCaseInsensitiveContains(text) }.prefix(limit))
    }

    func threadFacts(_ ids: [ThreadSummary.ID]) throws -> [MailFacts] {
        stored.filter { ids.contains($0.id) }.sorted { $0.date > $1.date }.compactMap(facts(of:))
    }

    func messageFacts(inThreads ids: [ThreadSummary.ID]) throws -> [MailFacts] {
        allMessageFacts.filter { ids.contains($0.envelope.thread) }
    }

    func messageFacts(matching condition: MailCondition, in context: MailCondition.Context) throws -> [MailFacts] {
        allMessageFacts.filter { condition.matches($0, in: context) }
    }

    func threadFacts(matching condition: MailCondition, in context: MailCondition.Context) throws -> [MailFacts] {
        try threadFacts(stored.map(\.id)).filter { condition.matches($0, in: context) }
    }

    private func facts(of thread: ThreadSummary) -> MailFacts? {
        accountList.first { $0.id == thread.id.accountID }.map {
            MailFacts(thread: thread, account: $0, labelNames: names(in: $0.id))
        }
    }

    /// The mailboxes' names by label ID, as the store gives them.
    private func names(in account: AccountID) -> [String: String] {
        let mailboxes = (try? mailboxes(of: account)) ?? []
        return Dictionary(
            mailboxes.compactMap { named in named.mailbox.labelID.map { ($0, named.name) } },
            uniquingKeysWith: { first, _ in first })
    }

    /// Every cached message, newest first, with the body text the store would keep.
    private var allMessageFacts: [MailFacts] {
        stored.flatMap { thread in
            (cached[thread.id] ?? []).compactMap { message in
                accountList.first { $0.id == thread.id.accountID }.map {
                    MailFacts(
                        message: message, bodyText: message.body.text, thread: thread, account: $0,
                        labelNames: names(in: $0.id))
                }
            }
        }.sorted { $0.envelope.date > $1.envelope.date }
    }

    /// Returns an undo that names `action` itself, so a test can tell which change an undo takes back.
    func perform(_ action: ThreadAction, on threads: [ThreadSummary.ID]) throws -> MailCommands.Undo {
        performed.record(action, on: threads)
        return MailCommands.Undo(
            intents: Dictionary(grouping: threads, by: \.accountID).mapValues { ids in
                ids.map { OutboxIntent(threadID: $0.threadID, action: action, createdAt: .distantPast) }
            })
    }

    func pin(_ threads: [ThreadSummary.ID], _ pinned: Bool) throws -> MailCommands.Undo {
        performed.recordPin(pinned, on: threads)
        return MailCommands.Undo(pins: Dictionary(uniqueKeysWithValues: threads.map { ($0, !pinned) }))
    }

    func snooze(_ threads: [ThreadSummary.ID], until date: Date?) throws -> MailCommands.Undo {
        performed.recordSnooze(until: date, on: threads)
        return MailCommands.Undo(snoozes: Dictionary(uniqueKeysWithValues: threads.map { ($0, SnoozeState?.none) }))
    }

    func unsubscribe(_ unsubscribe: Unsubscribe, account: AccountID) throws -> ListUnsubscriber.Outcome {
        performed.recordUnsubscribe(unsubscribe)
        return unsubscribing
    }

    /// Answers the cached message as the app does, quoted in English.
    func answer(_ answer: Answer, to message: Message.ID, inThread thread: ThreadSummary.ID) throws -> Draft? {
        guard let messages = cached[thread], let index = messages.firstIndex(where: { $0.id == message }),
            let account = accountList.first(where: { $0.id == thread.accountID })
        else { return nil }
        return answer.draft(
            answering: Array(messages[...index]), accountEmail: account.email, aliases: account.aliases,
            wording: .english)
    }

    func send(_ draft: Draft, at date: Date?) throws { performed.recordSend(draft, at: date) }

    func refresh() throws { performed.recordRefresh() }

    func undo(_ undo: MailCommands.Undo) throws {
        performed.recordUndo(of: undo)
    }

    @MainActor func open(_ route: Route) {}
}

/// The actions performed, per thread ID, in order, and the actions whose undos ran, once per thread, in order.
final class Performed: Sendable {
    private let actions = Mutex<[String: [ThreadAction]]>([:])
    private let undoneActions = Mutex<[ThreadAction]>([])
    private let pinChanges = Mutex<[String: [Bool]]>([:])
    private let snoozeChanges = Mutex<[String: [Date?]]>([:])
    private let unsubscribes = Mutex<[Unsubscribe]>([])
    private let refreshes = Mutex(0)
    private let sends = Mutex<[(draft: Draft, date: Date?)]>([])

    func recordSend(_ draft: Draft, at date: Date?) { sends.withLock { $0.append((draft, date)) } }

    /// Each message sent, with when it was asked to go (`nil` for now), in order.
    var sent: [(draft: Draft, date: Date?)] { sends.withLock { $0 } }

    func record(_ action: ThreadAction, on threads: [ThreadSummary.ID]) {
        actions.withLock { actions in
            for thread in threads { actions[thread.threadID, default: []].append(action) }
        }
    }

    func on(_ thread: String) -> [ThreadAction] { actions.withLock { $0[thread] ?? [] } }

    func recordPin(_ pinned: Bool, on threads: [ThreadSummary.ID]) {
        pinChanges.withLock { pins in
            for thread in threads { pins[thread.threadID, default: []].append(pinned) }
        }
    }

    /// Each pin (`true`) and unpin (`false`) asked for the thread, in order.
    func pins(of thread: String) -> [Bool] { pinChanges.withLock { $0[thread] ?? [] } }

    func recordUndo(of undo: MailCommands.Undo) {
        undoneActions.withLock { $0.append(contentsOf: undo.intents.values.joined().map(\.action)) }
    }

    var undone: [ThreadAction] { undoneActions.withLock { $0 } }

    func recordSnooze(until date: Date?, on threads: [ThreadSummary.ID]) {
        snoozeChanges.withLock { snoozes in
            for thread in threads { snoozes[thread.threadID, default: []].append(date) }
        }
    }

    /// Each wake date asked for the thread, in order; `nil` for an unsnooze.
    func snoozes(of thread: String) -> [Date?] { snoozeChanges.withLock { $0[thread] ?? [] } }

    func recordUnsubscribe(_ unsubscribe: Unsubscribe) { unsubscribes.withLock { $0.append(unsubscribe) } }

    var unsubscribed: [Unsubscribe] { unsubscribes.withLock { $0 } }

    func recordRefresh() { refreshes.withLock { $0 += 1 } }

    var refreshCount: Int { refreshes.withLock { $0 } }
}
