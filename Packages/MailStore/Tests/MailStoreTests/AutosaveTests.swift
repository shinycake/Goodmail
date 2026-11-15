import Foundation
import MailCore
import Testing

@testable import MailStore

/// A draft saved as it is written: kept on the device at once, sent on to the provider once per wait, and always
/// replacing the provider's one copy of it.
struct AutosaveTests {
    private let bench: SendBench
    private var database: MailDatabase { bench.database }
    private var server: FakeMailServer { bench.server }
    private var account: AccountID { bench.account }

    init() throws {
        bench = try SendBench()
    }

    private func commands() -> MailCommands { bench.commands() }

    /// Delivers as a launch would once every wait has passed.
    @discardableResult
    private func deliverLater() async throws -> [Draft] {
        try await bench.deliver(with: bench.sender(at: .distantFuture))
    }

    private func subject(of draft: String) -> String? {
        server.drafts[draft].map { String(decoding: $0.raw, as: UTF8.self) }?
            .firstMatch(of: /Subject: (.*)\r\n/).map { String($0.1) }
    }

    @Test func savesWhileWritingWaitTogetherAndKeepTheLatest() async throws {
        var draft = bench.draft("P")
        try await commands().autosave(draft, after: .seconds(20))
        let first = try #require(try database.dueMessages(for: account, by: .distantFuture).first)
        draft.subject = "Plan"
        try await commands().autosave(draft, after: .seconds(20))

        let queued = try database.dueMessages(for: account, by: .distantFuture)
        #expect(queued.map(\.draft.subject) == ["Plan"], "one save, with the newest draft")
        #expect(queued.first?.sendAt == first.sendAt, "the wait runs from the first save, not the last")
        #expect(try await bench.deliver().isEmpty, "not yet due")
        #expect(server.drafts.isEmpty)

        try await deliverLater()
        #expect(Array(server.drafts.keys) == ["d1"])
        #expect(subject(of: "d1") == "Plan")
    }

    @Test func eachSaveReplacesTheCopyTheLastOneLeft() async throws {
        var draft = bench.draft("One")
        try await commands().autosave(draft, after: .zero)
        try await deliverLater()
        draft.subject = "Two"
        try await commands().autosave(draft, after: .zero)
        try await deliverLater()
        #expect(Array(server.drafts.keys) == ["d2"], "d1 was replaced, though the draft never knew its ID")
        #expect(subject(of: "d2") == "Two")
        draft.subject = "Three"
        try await commands().saveDraft(draft)
        try await deliverLater()
        #expect(Array(server.drafts.keys) == ["d3"])
    }

    @Test func sendingOrDeletingRemovesTheAutosavedCopy() async throws {
        let sent = bench.draft("Sent")
        try await commands().autosave(sent, after: .zero)
        let deleted = bench.draft("Deleted")
        try await commands().autosave(deleted, after: .zero)
        try await deliverLater()
        #expect(server.drafts.count == 2)

        try await commands().send(sent, after: .zero)
        try await commands().deleteDraft(deleted)
        try await deliverLater()
        #expect(server.drafts.isEmpty)
        #expect(server.sent.count == 1)
    }

    @Test func aDraftNeverSavedIsDeletedWithoutTouchingTheProvider() async throws {
        try await server.saveDraft(Data(), inThread: nil, replacing: nil)
        try await commands().deleteDraft(bench.draft())
        try await deliverLater()
        #expect(Array(server.drafts.keys) == ["d1"], "someone else's draft stays")
    }

    @Test func aSaveDoesNotTakeThePlaceOfASendOrDelete() async throws {
        var draft = bench.draft("Going")
        try await commands().send(draft, after: .seconds(10))
        draft.subject = "Late save"
        try await commands().autosave(draft, after: .zero)
        let queued = try database.dueMessages(for: account, by: .distantFuture)
        #expect(queued.map(\.purpose) == [.send])
        #expect(queued.map(\.draft.subject) == ["Going"])
    }

    @Test func aSaveThatGoesWhileANewerOneArrivesLeavesTheNewerOne() throws {
        var draft = bench.draft("Old")
        try database.enqueueSave(OutgoingMessage(draft: draft, purpose: .saveDraft, sendAt: .now))
        let taken = try #require(try database.dueMessages(for: account, by: .distantFuture).first)
        draft.subject = "New"
        try database.enqueueSave(OutgoingMessage(draft: draft, purpose: .saveDraft, sendAt: .now))

        #expect(try database.finish(taken) == false)
        #expect(try database.dueMessages(for: account, by: .distantFuture).map(\.draft.subject) == ["New"])
        let newer = try #require(try database.dueMessages(for: account, by: .distantFuture).first)
        #expect(try database.finish(newer))
        #expect(try database.dueMessages(for: account, by: .distantFuture).isEmpty)
    }

    @Test func theSavedCopyIsKeptPerDraftUntilForgotten() throws {
        let draft = bench.draft()
        let copy = Message.ID(accountID: account, messageID: "d9")
        #expect(try database.savedCopy(of: draft.id) == nil)
        try database.setSavedCopy(copy, of: draft.id)
        #expect(try database.savedCopy(of: draft.id) == copy)
        try database.setSavedCopy(nil, of: draft.id)
        #expect(try database.savedCopy(of: draft.id) == nil)
    }
}
