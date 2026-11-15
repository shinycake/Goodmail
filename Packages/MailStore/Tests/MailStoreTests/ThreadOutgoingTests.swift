import Foundation
import MailCore
import Testing

@testable import MailStore

/// A conversation follows what is queued to go in it, so the chat can draw its replies on their way.
struct ThreadOutgoingTests {
    private let bench: SendBench
    private var database: MailDatabase { bench.database }
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    init() throws {
        bench = try SendBench()
    }

    private func draft(_ subject: String, thread: String?) -> Draft {
        Draft(
            accountID: bench.account, to: [Contact(name: nil, address: "dana@example.com")], subject: subject,
            body: MessageBody(html: nil, plain: "Hi"), threadID: thread)
    }

    @Test func aThreadListsOnlyItsOwnQueuedMessagesInTheOrderTheyGo() async throws {
        let commands = MailCommands(store: database, replay: { _ in }, now: { start })
        try await commands.schedule(draft("Later", thread: "t"), at: start.addingTimeInterval(3600))
        try await commands.send(draft("Now", thread: "t"), after: .seconds(5))
        try await commands.send(draft("Elsewhere", thread: "other"), after: .seconds(5))
        try await commands.send(draft("New", thread: nil), after: .seconds(5))

        let thread = ThreadSummary.ID(accountID: bench.account, threadID: "t")
        var queued = database.outgoingMessages(inThread: thread).makeAsyncIterator()
        #expect(try await queued.next()?.map(\.draft.subject) == ["Now", "Later"])
    }
}
