import Foundation
import Testing

@testable import MailCore

/// Who Block Sender and VIPs act on, and what each keeps.
struct SenderStandingTests {
    private let mine = ["me@example.com", "alias@example.com"]

    @Test("An address is one person whatever its case or the space around it")
    func addressesAreFolded() throws {
        let address = try #require(SenderAddress(" Dana@Example.COM "))
        #expect(address.address == "dana@example.com")
        #expect(SenderAddress("dana@example.com") == address)
    }

    @Test("Text that isn't an address names no one", arguments: ["", "dana", "@example.com", "dana@", "  "])
    func notAnAddress(_ text: String) {
        #expect(SenderAddress(text) == nil)
    }

    @Test("Mail the reader sent, from any of their addresses, has no sender to block or mark")
    func theReaderIsNoSender() {
        #expect(SenderAddress(of: Contact(name: "Me", address: "ME@example.com"), notFrom: mine) == nil)
        #expect(SenderAddress(of: Contact(name: nil, address: "alias@example.com"), notFrom: mine) == nil)
        #expect(
            SenderAddress(of: Contact(name: "Dana", address: "dana@example.com"), notFrom: mine)
                == SenderAddress("dana@example.com"))
    }

    @Test("Several conversations share a sender only when every one is from the same person")
    func sharedSender() {
        let dana = Contact(name: "Dana", address: "dana@example.com")
        let danaAgain = Contact(name: "Dana Levi", address: "DANA@example.com")
        let noa = Contact(name: "Noa", address: "noa@example.com")
        #expect(SenderAddress.shared(by: [dana, danaAgain], notFrom: mine) == SenderAddress("dana@example.com"))
        #expect(SenderAddress.shared(by: [dana, noa], notFrom: mine) == nil)
        #expect(SenderAddress.shared(by: [], notFrom: mine) == nil)
        #expect(SenderAddress.shared(by: [dana, Contact(name: nil, address: "me@example.com")], notFrom: mine) == nil)
    }

    @Test("VIPs keep the order they were added in, once each")
    func vipOrder() throws {
        var vips = VIPList(["Noa@example.com", "dana@example.com", "noa@example.com", "not an address"])
        #expect(vips.addresses == ["noa@example.com", "dana@example.com"])
        let lior = try #require(SenderAddress("lior@example.com"))
        vips.set(lior, isVIP: true)
        vips.set(lior, isVIP: true)
        #expect(vips.addresses == ["noa@example.com", "dana@example.com", "lior@example.com"])
        vips.set(try #require(SenderAddress("NOA@example.com")), isVIP: false)
        #expect(vips.addresses == ["dana@example.com", "lior@example.com"])
        #expect(vips.contains(lior))
        #expect(!vips.contains(try #require(SenderAddress("noa@example.com"))))
    }

    @Test("The VIPs' filter takes mail from any VIP, and with none it takes nothing")
    func vipCondition() {
        let facts = { (address: String) in
            MailFacts(
                thread: ThreadSummary(
                    id: ThreadSummary.ID(accountID: AccountID(rawValue: "a1"), threadID: address), subject: "Hi",
                    snippet: "", sender: Contact(name: nil, address: address), date: .now, isUnread: true,
                    messageCount: 1, labelIDs: [SystemLabel.inbox]),
                account: Account(
                    id: AccountID(rawValue: "a1"), email: "me@example.com", color: .teal, service: .gmail),
                labelNames: [:])
        }
        let vips = VIPList(["dana@example.com", "noa@example.com"])
        #expect(vips.condition.matches(facts("Dana@example.com")))
        #expect(vips.condition.matches(facts("noa@example.com")))
        #expect(!vips.condition.matches(facts("lior@example.com")))
        #expect(!VIPList().condition.matches(facts("dana@example.com")))
    }
}
