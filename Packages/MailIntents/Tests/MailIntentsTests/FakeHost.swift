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

    func cachedMessages(inThread id: ThreadSummary.ID) throws -> [Message] { cached[id] ?? [] }

    func perform(_ action: ThreadAction, on threads: [ThreadSummary.ID]) throws -> MailCommands.Undo {
        performed.record(action, on: threads)
        return MailCommands.Undo()
    }

    @MainActor func open(_ route: Route) {}
}

/// The actions performed, per thread ID, in order.
final class Performed: Sendable {
    private let actions = Mutex<[String: [ThreadAction]]>([:])

    func record(_ action: ThreadAction, on threads: [ThreadSummary.ID]) {
        actions.withLock { actions in
            for thread in threads { actions[thread.threadID, default: []].append(action) }
        }
    }

    func on(_ thread: String) -> [ThreadAction] { actions.withLock { $0[thread] ?? [] } }
}
