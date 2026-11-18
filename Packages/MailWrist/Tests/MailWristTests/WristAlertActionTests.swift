import Foundation
import MailCore
import Testing

@testable import MailWrist

struct WristAlertActionTests {
    private let gmail = AccountID(rawValue: "gmail")
    private let icloud = AccountID(rawValue: "icloud")
    private let now = Date(timeIntervalSince1970: 1_000)
    private var sources: [AccountID: WristAccountSource] { [gmail: .direct, icloud: .relayed(.service)] }
    private var conversation: ThreadSummary.ID { ThreadSummary.ID(accountID: gmail, threadID: "t1") }

    @Test(arguments: [
        (WristAlertAction.markRead, WristCommand.Kind.markRead(true)),
        (.archive, .archive),
        (.trash, .trash),
    ])
    func eachActionRunsOnTheWatch(action: WristAlertAction, kind: WristCommand.Kind) throws {
        let command = try #require(action.command(on: .thread(conversation), sources: sources, now: now))
        #expect(command.threads == [conversation])
        #expect(command.kind == kind)
        #expect(command.executor == .watch)
        #expect(command.madeAt == now)
    }

    @Test func aReplySendsItsWordsAndAnEmptyOneNothing() {
        let reply = WristAlertAction.reply.command(
            on: .thread(conversation), text: " Sounds good \n", sources: sources, now: now)
        #expect(reply?.kind == .reply("Sounds good"))
        #expect(
            WristAlertAction.reply.command(on: .thread(conversation), text: "  ", sources: sources, now: now) == nil)
        #expect(WristAlertAction.reply.command(on: .thread(conversation), sources: sources, now: now) == nil)
    }

    @Test func aRelayedAccountOrTheInboxMakesNoCommand() {
        let relayed = ThreadSummary.ID(accountID: icloud, threadID: "1")
        #expect(WristAlertAction.archive.command(on: .thread(relayed), sources: sources, now: now) == nil)
        #expect(WristAlertAction.archive.command(on: .inbox, sources: sources, now: now) == nil)
    }

    @Test func theIdentifiersMatchTheIPhonesAlertActions() {
        #expect(WristAlertAction.allCases.map(\.rawValue) == ["reply", "markRead", "archive", "trash"])
    }
}
