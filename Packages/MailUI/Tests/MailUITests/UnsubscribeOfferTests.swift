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
        offer.unsubscribe(try #require(offer.offer(in: messages)))
        await offer.settled()

        #expect(offer.offer(in: messages)?.state == .unsubscribed)
        #expect(self.offer().offer(in: [message(from: list, unsubscribe: oneClick, at: 5)])?.state == .unsubscribed)
    }

    @Test func aPageOpensAndAsksTheReaderToFinishThere() async throws {
        let page = URL(string: "https://example.com/leave-page")!
        var opened: [URL] = []
        let offer = offer(perform: { _ in .openPage(page) }, openURL: { opened.append($0) })
        let messages = [message(from: list, unsubscribe: .page(page), at: 1)]

        offer.unsubscribe(try #require(offer.offer(in: messages)))
        await offer.settled()

        #expect(opened == [page])
        #expect(offer.offer(in: messages)?.state == .pageOpened)
    }

    @Test func anOpenedPageIsNotRememberedUntilTheReaderSaysTheyFinished() async throws {
        let page = URL(string: "https://example.com/leave-page")!
        let messages = [message(from: list, unsubscribe: .page(page), at: 1)]
        let offer = offer(perform: { _ in .openPage(page) })

        offer.unsubscribe(try #require(offer.offer(in: messages)))
        await offer.settled()
        #expect(!memory.contains(list.address, account: account))
        #expect(self.offer().offer(in: messages)?.state == .offered)

        offer.finished(try #require(offer.offer(in: messages)))
        #expect(offer.offer(in: messages)?.state == .unsubscribed)
        #expect(self.offer().offer(in: messages)?.state == .unsubscribed)
    }

    @Test func finishingCountsOnlyAfterThePageOpened() throws {
        let offer = offer()
        let messages = [message(from: list, unsubscribe: oneClick, at: 1)]

        offer.finished(try #require(offer.offer(in: messages)))

        #expect(offer.offer(in: messages)?.state == .offered)
        #expect(!memory.contains(list.address, account: account))
    }

    @Test func aFailureCanBeTriedAgain() async throws {
        var attempts = 0
        let offer = offer(perform: { _ in
            attempts += 1
            if attempts == 1 { throw ListUnsubscriber.Failure.refused(status: 500) }
            return .done
        })
        let messages = [message(from: list, unsubscribe: oneClick, at: 1)]

        offer.unsubscribe(try #require(offer.offer(in: messages)))
        await offer.settled()
        let failed = try #require(offer.offer(in: messages))
        #expect(failed.state == .failed)
        #expect(!memory.contains(list.address, account: account))

        offer.unsubscribe(failed)
        await offer.settled()
        #expect(offer.offer(in: messages)?.state == .unsubscribed)
        #expect(attempts == 2)
    }

    /// The banner's offer is a snapshot: a second tap on it while the first request is out asks the list once.
    @Test func askingAgainWhileTheRequestIsOutAsksOnce() async throws {
        var attempts = 0
        let offer = offer(perform: { _ in
            attempts += 1
            return .done
        })
        let messages = [message(from: list, unsubscribe: oneClick, at: 1)]
        let shown = try #require(offer.offer(in: messages))

        offer.unsubscribe(shown)
        #expect(offer.offer(in: messages)?.state == .unsubscribing)
        offer.unsubscribe(shown)
        await offer.settled()

        #expect(attempts == 1)
        #expect(offer.offer(in: messages)?.state == .unsubscribed)
        offer.unsubscribe(shown)
        await offer.settled()
        #expect(attempts == 1, "a list already left isn't asked again from an old snapshot")
    }

    @Test(.timeLimit(.minutes(1))) func theRequestStopsWhenTheOfferGoes() async throws {
        let (started, starting) = AsyncStream<Void>.makeStream()
        let (stopped, stopping) = AsyncStream<Bool>.makeStream()
        var held: UnsubscribeOffer? = offer(perform: { _ in
            starting.yield()
            let slept: Void? = try? await Task.sleep(for: .seconds(60))
            stopping.yield(slept == nil)
            return .done
        })
        let messages = [message(from: list, unsubscribe: oneClick, at: 1)]
        held?.unsubscribe(try #require(held?.offer(in: messages)))
        for await _ in started { break }

        held = nil

        var cancelled = false
        for await stop in stopped {
            cancelled = stop
            break
        }
        #expect(cancelled, "the reader that held the offer went, and its request with it")
        #expect(!memory.contains(list.address, account: account))
    }
}
