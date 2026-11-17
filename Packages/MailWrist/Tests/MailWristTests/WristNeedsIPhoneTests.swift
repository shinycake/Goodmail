import Foundation
import MailCore
import Testing

@testable import MailWrist

/// While the watch reads some accounts itself, the rows of the others say they need the iPhone once it has been quiet
/// for a while, so the reader can tell which mail is current.
struct WristNeedsIPhoneTests {
    private let madeAt = Date(timeIntervalSince1970: 1_800_000_000)
    private let gmail = AccountID(rawValue: "gmail")
    private let icloud = AccountID(rawValue: "icloud")

    private func mailbox(sources: [AccountID: WristAccountSource]) -> WristMailbox {
        let phone = WristSnapshot(
            madeAt: madeAt,
            accounts: [
                WristAccount(id: gmail, address: "me@gmail.com", color: .teal, unread: 0, service: .gmail),
                WristAccount(id: icloud, address: "me@icloud.com", color: .orange, unread: 0, service: .icloud),
            ], rows: [])
        var mailbox = WristMailbox()
        mailbox.receive(phone, now: madeAt)
        mailbox.receiveOwn(WristSnapshot(madeAt: madeAt, accounts: [], rows: []), sources: sources, now: madeAt)
        return mailbox
    }

    private func minutes(_ minutes: Double) -> Date { madeAt.addingTimeInterval(minutes * 60) }

    @Test func aRelayedAccountNeedsTheIPhoneOnceItIsQuiet() {
        let mailbox = mailbox(sources: [gmail: .direct, icloud: .relayed(.service)])

        #expect(!mailbox.needsIPhone(icloud, now: minutes(10)))
        #expect(mailbox.needsIPhone(icloud, now: minutes(31)))
    }

    @Test func anAccountTheWatchReadsItselfNeverDoes() {
        let mailbox = mailbox(sources: [gmail: .direct, icloud: .relayed(.service)])

        #expect(!mailbox.needsIPhone(gmail, now: minutes(120)))
    }

    @Test func withoutAnyDirectAccountNoRowSaysSo() {
        let mailbox = mailbox(sources: [gmail: .relayed(.switchedOff), icloud: .relayed(.service)])

        #expect(!mailbox.needsIPhone(icloud, now: minutes(120)))
    }
}
