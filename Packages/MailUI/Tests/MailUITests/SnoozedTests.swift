import Foundation
import MailCore
import Testing

@testable import MailUI

/// The Snoozed list shows each thread by its sender and subject, and opens it to read where it now is.
@MainActor
struct SnoozedTests {
    private let account = Account(id: AccountID(rawValue: "a1"), email: "me@example.com", color: .teal, service: .gmail)

    private func snoozed(_ subject: String, wakeAt: Date) -> SnoozedThread {
        SnoozedThread(
            thread: ThreadSummary(
                id: ThreadSummary.ID(accountID: account.id, threadID: subject), subject: subject, snippet: "",
                sender: Contact(name: "Dana", address: "dana@example.com"), date: .now, isUnread: false,
                messageCount: 1, labelIDs: []),
            wakeAt: wakeAt)
    }

    @Test func rowsShowTheSenderAndSubjectAndOpenInAllMail() async {
        var routes: [Route] = []
        let wakeAt = Date.now.addingTimeInterval(3600)
        let viewModel = SnoozedViewModel(
            accounts: [account],
            threads: {
                AsyncThrowingStream {
                    $0.yield([self.snoozed("Lunch", wakeAt: wakeAt), self.snoozed("", wakeAt: wakeAt)])
                    $0.finish()
                }
            },
            actions: MailActions(commands: MailCommands(store: NoStore(), replay: { _ in })),
            navigate: { routes.append($0) })
        #expect(viewModel.content == .loading)
        await viewModel.observe()

        guard case .loaded(let rows) = viewModel.content else {
            Issue.record("still loading")
            return
        }
        #expect(rows.map(\.title) == ["Dana", "Dana"])
        #expect(rows.map(\.subtitle) == ["Lunch", "No Subject"])
        #expect(rows.first?.time == ScheduledTime.text(for: wakeAt))
        #expect(rows.first?.accountColor == nil, "one account needs no color")

        viewModel.open(rows[0].id)
        #expect(routes == [.thread(rows[0].id, in: .allMail)])
    }
}

/// A store with nothing in it, for view models whose actions these tests don't take.
private final class NoStore: MailCommands.Store, @unchecked Sendable {
    func enqueue(_ message: OutgoingMessage) throws {}
    func cancel(_ id: Draft.ID) throws -> OutgoingMessage? { nil }
    func dueMessages(for account: AccountID, by date: Date) throws -> [OutgoingMessage] { [] }
    func nextSendDate(for account: AccountID) throws -> Date? { nil }
    func uploadingMessages(for account: AccountID) throws -> [OutgoingMessage] { [] }
    func update(_ id: Draft.ID, from expected: OutgoingMessage.Delivery, to message: OutgoingMessage?) throws -> Bool {
        false
    }
    func requeue(_ id: Draft.ID, as purpose: OutgoingMessage.Purpose, at date: Date) throws -> OutgoingMessage? {
        nil
    }
    func remove(_ id: Draft.ID) throws {}
    func sender(for account: AccountID) throws -> Contact { Contact(name: nil, address: "") }
    func enqueue(_ intents: [OutboxIntent], account: AccountID) throws -> [String: Set<String>] { [:] }
    func pendingIntents(for account: AccountID) throws -> [OutboxIntent] { [] }
    func markSent(_ id: OutboxIntent.ID, at date: Date) throws {}
    func removeIntent(_ id: OutboxIntent.ID) throws {}
    func snoozes(of threads: [ThreadSummary.ID]) throws -> [ThreadSummary.ID: SnoozeState] { [:] }
    func setSnoozes(_ snoozes: [ThreadSummary.ID: SnoozeState?]) throws {}
    func dueSnoozes(by date: Date) throws -> [ThreadSummary.ID] { [] }
    func nextWakeDate() throws -> Date? { nil }
    func pruneSnoozes(at date: Date) throws {}
}
