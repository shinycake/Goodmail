import Foundation
import MailCore
import Synchronization
import Testing

@testable import MailStore

/// The Share extension keeps its message in the shared queue as it is written, so the app finds it in Drafts however
/// the sheet ends: the newest version only, the writer's delete honored, and an errand's version put back if it fails.
struct DraftKeeperTests {
    private let due = Date(timeIntervalSince1970: 1_900_000_000)

    private func queued(in bench: SendBench) throws -> [OutgoingMessage] {
        try bench.database.dueMessages(for: bench.account, by: .distantFuture)
    }

    @Test func versionsAskedForDuringAWriteCollapseIntoTheNewest() async throws {
        let bench = try SendBench()
        let writes = HeldWrites()
        let keeper = DraftKeeper(store: bench.database, keepAwake: writes.run)
        var draft = bench.draft()
        for word in ["H", "Hi", "Hi there"] {
            draft.body = MessageBody(plain: word)
            keeper.keep(.written(draft, by: due))
        }
        writes.release()
        await keeper.settle()

        #expect(writes.runs == 2, "the first, then only the newest of the rest")
        #expect(try queued(in: bench).map(\.draft.body.plain) == ["Hi there"])
        #expect(try queued(in: bench).map(\.purpose) == [.saveDraft])
    }

    @Test func aWriteGivenNoTimeLeavesTheVersionBefore() async throws {
        let bench = try SendBench()
        var draft = bench.draft()
        draft.body = MessageBody(plain: "Kept")
        let keeper = DraftKeeper(store: bench.database)
        keeper.keep(.written(draft, by: due))
        await keeper.settle()

        draft.body = MessageBody(plain: "Never written")
        let skipping = DraftKeeper(store: bench.database, keepAwake: { _ in })
        skipping.keep(.written(draft, by: due))
        await skipping.settle()

        #expect(try queued(in: bench).map(\.draft.body.plain) == ["Kept"])
    }

    @Test func deletingTakesBackTheSaveAndRemovesOnlyACopyTheAppSaved() async throws {
        let bench = try SendBench()
        let keeper = DraftKeeper(store: bench.database)
        let never = bench.draft("Never saved")
        keeper.keep(.written(never, by: due))
        keeper.keep(.deleted(never))
        await keeper.settle()
        #expect(try queued(in: bench).isEmpty, "nothing for the app to do")

        let saved = bench.draft("Saved by the app")
        try bench.database.setSavedCopy(Message.ID(accountID: bench.account, messageID: "d1"), of: saved.id)
        keeper.keep(.deleted(saved))
        await keeper.settle()
        #expect(try queued(in: bench).map(\.purpose) == [.deleteDraft])
    }

    @Test func anErrandTakesTheWaitingSaveAndCanPutItBack() async throws {
        let bench = try SendBench()
        let keeper = DraftKeeper(store: bench.database)
        let draft = bench.draft()
        keeper.keep(.written(draft, by: due))
        await keeper.settle()

        let taken = try #require(await keeper.take(draft.id))
        #expect(try queued(in: bench).isEmpty)

        keeper.restore(taken)
        await keeper.settle()
        #expect(try queued(in: bench).map(\.id) == [draft.id])
        #expect(try queued(in: bench).map(\.sendAt) == [due])
    }

    @Test func autosaveIsDueOnceItsWaitPasses() {
        let draft = Draft(accountID: AccountID(rawValue: "a1"))
        let message = OutgoingMessage.autosave(draft, after: .seconds(20), at: due)

        #expect(message.purpose == .saveDraft)
        #expect(message.sendAt == due.addingTimeInterval(20))
    }
}

/// Holds every write until `release`, counting the writes that ran.
private final class HeldWrites: Sendable {
    private struct State {
        var held = true
        var waiting: [CheckedContinuation<Void, Never>] = []
        var runs = 0
    }

    private let state = Mutex(State())

    var runs: Int { state.withLock { $0.runs } }

    func run(_ write: @escaping @Sendable () -> Void) async {
        await withCheckedContinuation { continuation in
            let goes = state.withLock { state in
                if state.held { state.waiting.append(continuation) }
                return !state.held
            }
            if goes { continuation.resume() }
        }
        write()
        state.withLock { $0.runs += 1 }
    }

    func release() {
        let waiting = state.withLock { state in
            state.held = false
            defer { state.waiting = [] }
            return state.waiting
        }
        for continuation in waiting { continuation.resume() }
    }
}
