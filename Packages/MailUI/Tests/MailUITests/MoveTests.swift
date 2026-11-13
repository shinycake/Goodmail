import Foundation
import MailCore
import Testing

@testable import MailUI

/// Threads' labels in memory, changed by the actions queued on them.
private final class LabelStore: MailCommands.Store, @unchecked Sendable {
    var labels: [String: Set<String>]
    var queued: [OutboxIntent] = []

    init(_ labels: [String: Set<String>]) { self.labels = labels }

    func enqueue(_ intents: [OutboxIntent], account: AccountID) throws -> [String: Set<String>] {
        var before: [String: Set<String>] = [:]
        for intent in intents {
            guard let current = labels[intent.threadID] else { continue }
            before[intent.threadID] = before[intent.threadID] ?? current
            labels[intent.threadID] = intent.action.applied(to: current)
            queued.append(intent)
        }
        return before
    }

    func pendingIntents(for account: AccountID) throws -> [OutboxIntent] { queued }
    func markSent(_ id: OutboxIntent.ID, at date: Date) throws {}
    func removeIntent(_ id: OutboxIntent.ID) throws {}
    func enqueue(_ message: OutgoingMessage) throws {}
    func cancel(_ id: Draft.ID) throws -> OutgoingMessage? { nil }
    func dueMessages(for account: AccountID, by date: Date) throws -> [OutgoingMessage] { [] }
    func nextSendDate(for account: AccountID) throws -> Date? { nil }
    func requeue(_ id: Draft.ID, as purpose: OutgoingMessage.Purpose, at date: Date) throws -> OutgoingMessage? {
        nil
    }
    func markFailed(_ id: Draft.ID, reason: SendFailure) throws {}
    func remove(_ id: Draft.ID) throws {}
    func sender(for account: AccountID) throws -> Contact { Contact(name: nil, address: "") }
    func snoozes(of threads: [ThreadSummary.ID]) throws -> [ThreadSummary.ID: SnoozeState] { [:] }
    func setSnoozes(_ snoozes: [ThreadSummary.ID: SnoozeState?]) throws {}
    func dueSnoozes(by date: Date) throws -> [ThreadSummary.ID] { [] }
    func nextWakeDate() throws -> Date? { nil }
    func pruneSnoozes(at date: Date) throws {}
}

@MainActor
struct MoveViewModelTests {
    private let work = AccountID(rawValue: "work")
    private let home = AccountID(rawValue: "home")
    private let labels = [
        MailLabel(id: "INBOX", name: "INBOX", kind: .system),
        MailLabel(id: "Label_1", name: "Clients", kind: .user, color: "#16a765"),
        MailLabel(id: "Label_2", name: "Receipts", kind: .user),
        MailLabel(id: "Label_3", name: "Old", kind: .user, isHidden: true),
    ]

    private func id(_ thread: String, in account: AccountID? = nil) -> ThreadSummary.ID {
        ThreadSummary.ID(accountID: account ?? work, threadID: thread)
    }

    private func model(
        _ threads: [ThreadSummary.ID], from mailbox: Mailbox, actions: MailActions? = nil
    ) -> MoveViewModel {
        MoveViewModel(threads: threads, from: mailbox, labels: { _ in labels }, actions: actions)
    }

    @Test func placesComeFirstThenVisibleUserLabelsWithTheirColors() {
        let model = model([id("t")], from: .inbox)
        #expect(model.places.map(\.destination) == [.archive, .spam, .trash], "not the Inbox it is already in")
        #expect(model.labels.map(\.name) == ["Clients", "Receipts"])
        #expect(model.labels.first?.color == "#16a765")
    }

    @Test func theLabelBeingReadIsNotOffered() {
        let model = model([id("t")], from: Mailbox(labelID: "Label_1", accountID: work))
        #expect(model.places.map(\.destination) == [.inbox, .archive, .spam, .trash])
        #expect(model.labels.map(\.destination) == [.label("Label_2")])
        #expect(self.model([id("t")], from: .allMail).places.count == 4)
    }

    @Test func threadsFromSeveralAccountsGetNoLabels() {
        let model = model([id("a", in: work), id("b", in: home)], from: .inbox)
        #expect(model.labels.isEmpty, "each account has its own labels")
        #expect(model.places.count == 3)
    }

    @Test func movingAppliesOneChangeWithAToastThatUndoesIt() async throws {
        let store = LabelStore(["t1": ["INBOX", "Label_2"], "t2": ["INBOX"]])
        let actions = MailActions(commands: MailCommands(store: store, replay: { _ in }), toastDuration: .seconds(60))
        let model = model([id("t1"), id("t2")], from: .inbox, actions: actions)

        model.move(to: try #require(model.labels.first))
        await actions.settled()
        #expect(store.labels == ["t1": ["Label_2", "Label_1"], "t2": ["Label_1"]])
        #expect(store.queued.map(\.action) == Array(repeating: .move(to: .label("Label_1"), from: .inbox), count: 2))
        #expect(actions.toast?.message == "2 threads moved to Clients")

        actions.undoLast()
        await actions.settled()
        #expect(store.labels == ["t1": ["INBOX", "Label_2"], "t2": ["INBOX"]])
        #expect(actions.toast == nil)
    }

    @Test func movingFromALabelTakesItAway() async throws {
        let store = LabelStore(["t": ["INBOX", "Label_1"]])
        let actions = MailActions(commands: MailCommands(store: store, replay: { _ in }), toastDuration: .seconds(60))
        let model = model([id("t")], from: Mailbox(labelID: "Label_1", accountID: work), actions: actions)

        model.move(to: try #require(model.places.first { $0.destination == .archive }))
        await actions.settled()
        #expect(store.labels["t"] == [])
        #expect(actions.toast?.message == "Moved to Archive")
    }

    @Test func listsAndTheReaderAskToMoveFromTheirMailbox() async {
        let label = Mailbox(labelID: "Label_1", accountID: work)
        var routes: [Route] = []
        let list = MailboxViewModel(
            mailbox: label, accounts: [], source: .flat { AsyncThrowingStream { $0.finish() } }, refresh: {},
            navigate: { routes.append($0) })
        list.open(id("t"))
        list.move([id("t")])
        #expect(routes == [.thread(id("t"), in: label), .move([id("t")], from: label)])
    }

    @Test func theReaderNoticesWhenTheThreadLeavesItsMailbox() async {
        let thread = ThreadSummary(
            id: id("t"), subject: "Plan", snippet: "", sender: Contact(name: nil, address: "a@example.com"),
            date: .now, isUnread: false, messageCount: 1, labelIDs: ["Label_1"])
        func message(_ labels: Set<String>) -> Message {
            Message(
                id: Message.ID(accountID: work, messageID: "m"), threadID: "t", from: thread.sender, subject: "Plan",
                date: .now, labelIDs: labels, body: MessageBody(plain: ""))
        }
        var routes: [Route] = []
        var closes = 0
        let model = ThreadViewModel(
            thread: thread, mailbox: Mailbox(labelID: "Label_1", accountID: work), accountEmail: "me@example.com",
            accountColor: .blue, accountService: .gmail,
            messages: {
                AsyncThrowingStream {
                    $0.yield([message(["Label_1"])])
                    $0.yield([message(["Label_1", "STARRED"])])
                    $0.yield([message(["Label_2"])])
                    $0.yield([message(["Label_3"])])
                    $0.finish()
                }
            }, load: {}, attachmentData: { _, _ in Data() }, navigate: { routes.append($0) },
            close: { closes += 1 })
        model.move()
        #expect(routes == [.move([id("t")], from: Mailbox(labelID: "Label_1", accountID: work))])
        await model.observe()
        #expect(model.presence == .left)
        #expect(closes == 1, "The reader closes once, however many updates follow")
        model.perform(.archive)
        #expect(closes == 1)
    }

    @Test func leavingActionsCloseTheReaderOnceAndOthersDont() {
        var closes = 0
        let thread = ThreadSummary(
            id: id("t"), subject: "Plan", snippet: "", sender: Contact(name: nil, address: "a@example.com"),
            date: .now, isUnread: false, messageCount: 1, labelIDs: ["INBOX"])
        func reader() -> ThreadViewModel {
            ThreadViewModel(
                thread: thread, mailbox: .inbox, accountEmail: "me@example.com", accountColor: .blue,
                accountService: .gmail,
                messages: { AsyncThrowingStream { $0.finish() } }, load: {}, attachmentData: { _, _ in Data() },
                close: { closes += 1 })
        }
        let starring = reader()
        starring.perform(.star(true))
        #expect(starring.presence == .reading)
        #expect(closes == 0)
        for action in [ThreadAction.archive, .trash, .reportSpam, .markRead(false)] {
            let model = reader()
            model.perform(action)
            model.perform(action)
            #expect(model.presence == .left)
        }
        #expect(closes == 4)
    }
}
