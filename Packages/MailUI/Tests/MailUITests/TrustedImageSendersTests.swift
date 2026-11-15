import Foundation
import MailCore
import Testing

@testable import MailUI

/// Trusting a sender loads their remote images in every message from them, on this device, until Settings removes
/// them.
@MainActor
struct TrustedImageSendersTests {
    private let account = AccountID(rawValue: "a1")
    private let senders: TrustedImageSenders

    init() {
        senders = TrustedImageSenders(defaults: UserDefaults(suiteName: "TrustedImageSendersTests.\(UUID())")!)
    }

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
            }, load: {}, attachmentData: { _, _ in Data() }, trustedSenders: senders)
    }

    @Test func addressesCompareWithoutCaseAndStaySorted() {
        senders.trust(" News@Shop.example ")
        senders.trust("anna@example.com")
        senders.trust("news@shop.example")
        #expect(senders.addresses == ["anna@example.com", "news@shop.example"])
        #expect(senders.contains("NEWS@shop.example"))
    }

    @Test func anEmptyAddressIsNeverTrusted() {
        senders.trust("  ")
        #expect(senders.addresses.isEmpty)
    }

    @Test func distrustingRemovesOnlyThatSender() {
        senders.trust("a@example.com")
        senders.trust("b@example.com")
        senders.distrust("A@example.com")
        #expect(senders.addresses == ["b@example.com"])
    }

    @Test func loadingOnceAllowsOnlyThatMessage() async {
        let messages = [message("1", from: "news@shop.example"), message("2", from: "news@shop.example")]
        let model = model(messages)
        await model.observe()
        model.allowRemoteContent(in: messages[0].id)
        #expect(model.remoteContentAllowed == [messages[0].id])
        #expect(senders.addresses.isEmpty)
    }

    @Test func trustingASenderAllowsAllTheirMessagesAndIsRemembered() async throws {
        let news = [message("1", from: "news@shop.example"), message("2", from: "News@Shop.example")]
        let other = message("3", from: "anna@example.com")
        let model = model(news + [other])
        await model.observe()
        model.alwaysAllowRemoteContent(from: news[0].id)
        #expect(model.remoteContentAllowed == Set(news.map(\.id)))

        let later = self.model([message("4", from: "news@shop.example")])
        await later.observe()
        #expect(later.remoteContentAllowed.count == 1, "a thread opened later trusts them too")
    }

    @Test func aSenderRemovedInSettingsIsBlockedAgainInThreadsOpenedAfter() async {
        senders.trust("news@shop.example")
        senders.distrust("news@shop.example")
        let model = model([message("1", from: "news@shop.example")])
        await model.observe()
        #expect(model.remoteContentAllowed.isEmpty)
    }
}
