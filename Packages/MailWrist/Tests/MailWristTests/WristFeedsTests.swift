import Foundation
import MailCore
import Testing

@testable import MailWrist

/// The watch shows one Inbox from two feeds: its own for the accounts it reads itself, the iPhone's for the rest,
/// with what only the iPhone knows laid over.
struct WristFeedsTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let gmail = AccountID(rawValue: "gmail")
    private let icloud = AccountID(rawValue: "icloud")

    private func row(
        _ account: AccountID, _ id: String, minutesAgo: Double, unread: Bool = true, pinned: Bool = false
    ) -> WristRow {
        WristRow(
            id: ThreadSummary.ID(accountID: account, threadID: id), sender: Contact(name: nil, address: "a@x.com"),
            subject: id, snippet: "", date: now.addingTimeInterval(-minutesAgo * 60), isUnread: unread,
            messageCount: 1, isPinned: pinned, code: nil)
    }

    private func id(_ account: AccountID, _ thread: String) -> ThreadSummary.ID {
        ThreadSummary.ID(accountID: account, threadID: thread)
    }

    private func snapshot(_ rows: [WristRow], unread: [AccountID: Int] = [:], extras: WristExtras? = nil)
        -> WristSnapshot
    {
        WristSnapshot(
            madeAt: now,
            accounts: [
                WristAccount(id: gmail, address: "me@gmail.com", color: .teal, unread: unread[gmail] ?? 0),
                WristAccount(id: icloud, address: "me@icloud.com", color: .orange, unread: unread[icloud] ?? 0),
            ],
            rows: rows, extras: extras)
    }

    private let sources: [AccountID: WristAccountSource] = [
        AccountID(rawValue: "gmail"): .direct, AccountID(rawValue: "icloud"): .relayed(.service),
    ]

    private func shown(
        phone: WristSnapshot, own: WristSnapshot?, sources: [AccountID: WristAccountSource]? = nil,
        extras: WristExtras? = nil
    ) -> [String] {
        WristSnapshot.merged(phone: phone, own: own, sources: sources ?? self.sources, extras: extras).rows
            .map(\.id.threadID)
    }

    @Test func aDirectAccountsRowsComeFromTheWatchAndARelayedOnesFromTheIPhone() {
        let phone = snapshot(
            [row(gmail, "phone-old", minutesAgo: 1), row(icloud, "i1", minutesAgo: 2)], unread: [gmail: 1, icloud: 1])
        let own = snapshot(
            [row(gmail, "g-new", minutesAgo: 0), row(icloud, "stray", minutesAgo: 0)], unread: [gmail: 7])

        let merged = WristSnapshot.merged(phone: phone, own: own, sources: sources, extras: nil)

        #expect(merged.rows.map(\.id.threadID) == ["g-new", "i1"])
        #expect(merged.accounts.map(\.unread) == [7, 1])
        #expect(merged.accounts.map(\.address) == ["me@gmail.com", "me@icloud.com"], "the iPhone's accounts")
    }

    @Test func pinsAreLaidOverTheWatchsRows() {
        let own = snapshot([row(gmail, "g1", minutesAgo: 1), row(gmail, "g2", minutesAgo: 5)])
        let extras = WristExtras(pinned: [id(gmail, "g2")])

        let merged = WristSnapshot.merged(phone: snapshot([]), own: own, sources: sources, extras: extras)

        #expect(merged.rows.map(\.id.threadID) == ["g2", "g1"])
        #expect(merged.rows.map(\.isPinned) == [true, false])
    }

    @Test func threadsAsleepOrMutedOnTheIPhoneAreHidden() {
        let own = snapshot([
            row(gmail, "asleep", minutesAgo: 1), row(gmail, "muted", minutesAgo: 2), row(gmail, "kept", minutesAgo: 3),
        ])
        let extras = WristExtras(asleep: [id(gmail, "asleep")], muted: [id(gmail, "muted")])

        #expect(shown(phone: snapshot([]), own: own, extras: extras) == ["kept"])
    }

    @Test func accountsOutsideTheFocusAreHidden() {
        let phone = snapshot([row(icloud, "i1", minutesAgo: 2)], unread: [icloud: 1])
        let own = snapshot([row(gmail, "g1", minutesAgo: 1)], unread: [gmail: 1])
        let extras = WristExtras(focus: [icloud])

        let merged = WristSnapshot.merged(phone: phone, own: own, sources: sources, extras: extras)

        #expect(merged.rows.map(\.id.threadID) == ["i1"])
        #expect(merged.accounts.map(\.unread) == [0, 1])
    }

    @Test func aPinnedRowTheWatchDoesntHoldComesFromTheIPhone() {
        let phone = snapshot([
            row(gmail, "pinned-old", minutesAgo: 900, pinned: true), row(gmail, "unpinned", minutesAgo: 1),
        ])
        let own = snapshot([row(gmail, "g1", minutesAgo: 2)])
        let extras = WristExtras(pinned: [id(gmail, "pinned-old")])

        #expect(shown(phone: phone, own: own, extras: extras) == ["pinned-old", "g1"])
    }

    @Test func pinnedFirstThenNewestUpToTheRowLimit() {
        let own = snapshot((0..<30).map { row(gmail, "g\($0)", minutesAgo: Double($0)) })
        let phone = snapshot([row(icloud, "i-pinned", minutesAgo: 500, pinned: true)])

        let rows = shown(phone: phone, own: own)

        #expect(rows.count == WristSnapshot.rowLimit)
        #expect(rows.first == "i-pinned")
        #expect(Array(rows.dropFirst().prefix(2)) == ["g0", "g1"])
    }

    @Test func withNoOwnFeedItIsTheIPhonesSnapshot() {
        let phone = snapshot([row(gmail, "g1", minutesAgo: 1), row(icloud, "i1", minutesAgo: 2)], unread: [gmail: 1])

        #expect(WristSnapshot.merged(phone: phone, own: nil, sources: sources, extras: nil) == phone)
        let filling: [AccountID: WristAccountSource] = [gmail: .relayed(.filling), icloud: .relayed(.service)]
        #expect(
            WristSnapshot.merged(phone: phone, own: snapshot([]), sources: filling, extras: WristExtras()) == phone,
            "an account still filling is the iPhone's")
    }

    @Test func theMailboxKeepsTheLastExtrasWhileTheIPhoneIsAway() throws {
        var mailbox = WristMailbox()
        mailbox.receive(snapshot([], extras: WristExtras(muted: [id(gmail, "muted")])), now: now)
        mailbox.receive(snapshot([]), now: now)
        mailbox.receiveOwn(
            snapshot([row(gmail, "muted", minutesAgo: 1), row(gmail, "g1", minutesAgo: 2)]), sources: sources)

        #expect(try #require(mailbox.shown).rows.map(\.id.threadID) == ["g1"])
    }

    @Test func aMailboxStoredBeforeTheOwnFeedStillReads() throws {
        let old = Data(#"{"pending":[],"undelivered":[]}"#.utf8)
        let mailbox = try JSONDecoder().decode(WristMailbox.self, from: old)
        #expect(mailbox.own == nil)
        #expect(mailbox.sources.isEmpty)
        #expect(mailbox.extras == nil)
    }

    @Test func aMailboxWithBothFeedsReadsBack() throws {
        var mailbox = WristMailbox()
        mailbox.receive(snapshot([], extras: WristExtras(pinned: [id(gmail, "g1")])), now: now)
        mailbox.receiveOwn(snapshot([row(gmail, "g1", minutesAgo: 1)]), sources: sources)
        let read = try JSONDecoder().decode(WristMailbox.self, from: JSONEncoder().encode(mailbox))
        #expect(read == mailbox)
    }
}
