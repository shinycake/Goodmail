import Foundation
import MailCore
import Testing

@testable import MailUI

/// Trust rules load remote images in every message they match, from a sender or a whole domain, on this device until
/// Settings removes them.
// They follow the store's streams, so one that never finishes fails the test instead of hanging the run.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct ImageTrustRulesTests {
    private let account = AccountID(rawValue: "a1")
    private let defaults = UserDefaults(suiteName: "ImageTrustRulesTests.\(UUID())")!
    private var rules: ImageTrustRules { ImageTrustRules(defaults: defaults) }

    private func message(_ id: String, from address: String) -> Message {
        Message(
            id: Message.ID(accountID: account, messageID: id), threadID: "t",
            from: Contact(name: nil, address: address), subject: "News", date: .now,
            body: MessageBody(html: "<img src=\"https://example.com/a.png\">"))
    }

    private func model(_ messages: [Message]) -> ThreadViewModel {
        ThreadViewModel(
            thread: ThreadSummary(
                id: .init(accountID: account, threadID: "t"), subject: "News", snippet: "",
                sender: messages[0].from, date: .now, isUnread: false, messageCount: messages.count, labelIDs: []),
            mailbox: .inbox, accountEmail: "me@example.com", accountColor: .blue,
            messages: {
                AsyncThrowingStream {
                    $0.yield(messages)
                    $0.finish()
                }
            }, load: {}, attachmentData: { _, _ in Data() }, imageTrust: rules)
    }

    @Test func rulesListDomainsFirstThenSendersAlphabetically() {
        rules.add(.sender("news@shop.example"))
        rules.add(.domain("zoo.example", subdomains: .included))
        rules.add(.sender("anna@example.com"))
        rules.add(.domain("bank.example", subdomains: .excluded))
        #expect(
            rules.all == [
                .domain("bank.example", subdomains: .excluded), .domain("zoo.example", subdomains: .included),
                .sender("anna@example.com"), .sender("news@shop.example"),
            ])
    }

    @Test func addingADomainAgainReplacesItsSubdomainChoice() {
        rules.add(.domain("shop.example", subdomains: .excluded))
        rules.add(.domain("shop.example", subdomains: .included))
        #expect(rules.all == [.domain("shop.example", subdomains: .included)])
    }

    @Test func aSenderAndTheirDomainAreSeparateRules() {
        rules.add(.sender("news@shop.example"))
        rules.add(.domain("shop.example", subdomains: .included))
        rules.remove(.sender("news@shop.example"))
        #expect(rules.all == [.domain("shop.example", subdomains: .included)])
    }

    @Test func editingARulePutsTheNewOneInItsPlace() {
        rules.add(.sender("news@shop.example"))
        rules.add(.domain("shop.example", subdomains: .excluded))
        rules.replace(.sender("news@shop.example"), with: .domain("shop.example", subdomains: .included))
        #expect(rules.all == [.domain("shop.example", subdomains: .included)])
    }

    @Test func sendersTrustedBeforeDomainRulesCarryOver() {
        defaults.set(["anna@example.com", "news@shop.example"], forKey: "trustedImageSenders")
        #expect(rules.all == [.sender("anna@example.com"), .sender("news@shop.example")])
        rules.add(.domain("shop.example", subdomains: .included))
        #expect(rules.all.count == 3)
        #expect(defaults.object(forKey: "trustedImageSenders") == nil, "the old list is folded in once")
    }

    @Test func loadingOnceAllowsOnlyThatMessage() async {
        let messages = [message("1", from: "news@shop.example"), message("2", from: "news@shop.example")]
        let model = model(messages)
        await model.observe()
        model.allowRemoteContent(in: messages[0].id)
        #expect(model.remoteContentAllowed == [messages[0].id])
        #expect(rules.all.isEmpty)
    }

    @Test func trustingASenderAllowsAllTheirMessagesAndIsRemembered() async throws {
        let news = [message("1", from: "news@shop.example"), message("2", from: "News@Shop.example")]
        let other = message("3", from: "anna@example.com")
        let model = model(news + [other])
        await model.observe()
        model.alwaysAllowRemoteContent(by: .sender("news@shop.example"))
        #expect(model.remoteContentAllowed == Set(news.map(\.id)))

        let later = self.model([message("4", from: "news@shop.example")])
        await later.observe()
        #expect(later.remoteContentAllowed.count == 1, "a thread opened later trusts them too")
    }

    @Test func trustingADomainAllowsEveryAddressAtItAndUnderIt() async {
        let messages = [
            message("1", from: "news@shop.example"), message("2", from: "deals@mail.shop.example"),
            message("3", from: "anna@example.com"),
        ]
        let model = model(messages)
        await model.observe()
        model.alwaysAllowRemoteContent(by: .domain("shop.example", subdomains: .included))
        #expect(model.remoteContentAllowed == [messages[0].id, messages[1].id])
    }

    @Test func aRuleRemovedInSettingsIsBlockedAgainInThreadsOpenedAfter() async {
        rules.add(.domain("shop.example", subdomains: .included))
        rules.remove(.domain("shop.example", subdomains: .included))
        let model = model([message("1", from: "news@shop.example")])
        await model.observe()
        #expect(model.remoteContentAllowed.isEmpty)
    }
}
