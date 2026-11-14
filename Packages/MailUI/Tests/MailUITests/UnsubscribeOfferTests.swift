import Foundation
import MailCore
import Testing

@testable import MailUI

/// A conversation from a mailing list offers to leave it, says how leaving went, and remembers the list it left.
@MainActor
struct UnsubscribeOfferTests {
    private let account = AccountID(rawValue: "a1")
    private let list = Contact(name: "Weekly News", address: "news@example.com")
    private let oneClick = Unsubscribe.oneClick(URL(string: "https://example.com/leave")!)
    private let memory: UnsubscribedLists

    init() {
        let suite = "UnsubscribeOfferTests.\(UUID().uuidString)"
        memory = UnsubscribedLists(defaults: UserDefaults(suiteName: suite)!)
    }

    private func message(from sender: Contact, unsubscribe: Unsubscribe?, at seconds: TimeInterval) -> Message {
        Message(
            id: Message.ID(accountID: account, messageID: "\(seconds)"), threadID: "t", from: sender,
            subject: "Weekly", date: Date(timeIntervalSince1970: seconds), body: MessageBody(plain: "Hi"),
            unsubscribe: unsubscribe)
    }

    private func offer(
        perform: @escaping (Unsubscribe) async throws -> ListUnsubscriber.Outcome = { _ in .done },
        openURL: @escaping (URL) -> Void = { _ in }
    ) -> UnsubscribeOffer {
        UnsubscribeOffer(
            account: account, accountEmail: "me@example.com", perform: perform, openURL: openURL, memory: memory)
    }

    @Test func theNewestListMessageIsOfferedButNotTheReadersOwnReply() throws {
        let messages = [
            message(from: list, unsubscribe: oneClick, at: 1),
            message(
                from: Contact(name: nil, address: "ME@example.com"),
                unsubscribe: .page(URL(string: "https://example.com/mine")!), at: 2),
        ]
        let shown = try #require(offer().offer(in: messages))
        #expect(shown == UnsubscribeOffer.Offer(list: list, unsubscribe: oneClick, state: .offered))
    }

    @Test func aConversationWithoutAListOffersNothing() {
        #expect(offer().offer(in: [message(from: list, unsubscribe: nil, at: 1)]) == nil)
    }

    @Test func unsubscribingIsRememberedForTheListsLaterMail() async throws {
        let messages = [message(from: list, unsubscribe: oneClick, at: 1)]
        let offer = offer()
        await offer.unsubscribe(try #require(offer.offer(in: messages)))

        #expect(offer.offer(in: messages)?.state == .unsubscribed)
        #expect(self.offer().offer(in: [message(from: list, unsubscribe: oneClick, at: 5)])?.state == .unsubscribed)
    }

    @Test func aPageOpensAndAsksTheReaderToFinishThere() async throws {
        let page = URL(string: "https://example.com/leave-page")!
        var opened: [URL] = []
        let offer = offer(perform: { _ in .openPage(page) }, openURL: { opened.append($0) })
        let messages = [message(from: list, unsubscribe: .page(page), at: 1)]

        await offer.unsubscribe(try #require(offer.offer(in: messages)))

        #expect(opened == [page])
        #expect(offer.offer(in: messages)?.state == .pageOpened)
    }

    @Test func aFailureCanBeTriedAgain() async throws {
        var attempts = 0
        let offer = offer(perform: { _ in
            attempts += 1
            if attempts == 1 { throw ListUnsubscriber.Failure.refused(status: 500) }
            return .done
        })
        let messages = [message(from: list, unsubscribe: oneClick, at: 1)]

        await offer.unsubscribe(try #require(offer.offer(in: messages)))
        let failed = try #require(offer.offer(in: messages))
        #expect(failed.state == .failed)
        #expect(!memory.contains(list.address, account: account))

        await offer.unsubscribe(failed)
        #expect(offer.offer(in: messages)?.state == .unsubscribed)
        #expect(attempts == 2)
    }
}
