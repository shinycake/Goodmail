import MailCore
import Testing

@testable import MailWrist

struct WristAlertTargetTests {
    private let gmail = AccountID(rawValue: "gmail")
    private let outlook = AccountID(rawValue: "outlook")
    private let icloud = AccountID(rawValue: "icloud")
    private var accounts: [WristAccount] {
        [
            WristAccount(id: gmail, address: "Me@Gmail.com", color: .teal, unread: 0, service: .gmail),
            WristAccount(id: outlook, address: "me@outlook.com", color: .blue, unread: 0, service: .outlook),
            WristAccount(id: icloud, address: "me@icloud.com", color: .orange, unread: 0, service: .icloud),
        ]
    }
    private var sources: [AccountID: WristAccountSource] {
        [gmail: .direct, outlook: .direct, icloud: .relayed(.service)]
    }

    private func target(_ payload: [AnyHashable: Any]) -> WristAlertTarget {
        WristAlertTarget(payload: payload, accounts: accounts, sources: sources)
    }

    @Test func aDirectAccountsAlertOpensItsConversation() {
        #expect(
            target(["account": "me@gmail.com", "threadID": "t1"])
                == .thread(ThreadSummary.ID(accountID: gmail, threadID: "t1")))
        #expect(
            target(["accountID": "outlook", "threadID": "c1"])
                == .thread(ThreadSummary.ID(accountID: outlook, threadID: "c1")))
    }

    @Test func withoutAThreadOrForARelayedAccountTheInboxOpens() {
        #expect(target(["account": "me@gmail.com"]) == .inbox)
        #expect(target(["accountID": "icloud", "threadID": "1"]) == .inbox)
    }

    @Test func aMalformedPayloadOpensTheInbox() {
        #expect(target([:]) == .inbox)
        #expect(target(["account": "someone@else.com", "threadID": "t1"]) == .inbox)
        #expect(target(["accountID": 7, "threadID": "t1"]) == .inbox)
        #expect(target(["account": "me@gmail.com", "threadID": ""]) == .inbox)
    }
}
