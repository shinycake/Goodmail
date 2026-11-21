import Foundation
import MailCore
import Testing

/// A reader shows a conversation's messages, says when it has none to show and why, and never says a conversation is
/// gone only because the store hadn't its messages yet.
struct ConversationContentTests {
    private let message = Message(
        id: Message.ID(accountID: AccountID(rawValue: "a"), messageID: "m"), threadID: "t",
        from: Contact(name: nil, address: "x@example.com"), subject: "s", date: .distantPast,
        body: MessageBody(plain: "Hi"))

    @Test func messagesShowAsTheyComeInEitherOrder() {
        var content = ConversationContent.loading
        content.received([])
        #expect(content == .loading, "the store hasn't them yet")
        content.fetched(.done(stored: true))
        #expect(content == .loading, "what was fetched comes through the store")
        content.received([message])
        #expect(content == .shown([message]))
        #expect(content.messages == [message])
    }

    @Test func aConversationTheServiceNoLongerHasIsGone() {
        var content = ConversationContent.loading
        content.fetched(.notFound)
        #expect(content == .unavailable(.gone))
    }

    @Test func messagesOnTheDeviceStayWhateverTheServiceSays() {
        // IMAP can't find a conversation whose keys it hasn't synced yet; one deleted leaves the store, which says so.
        var shown = ConversationContent.shown([message])
        shown.fetched(.notFound)
        #expect(shown == .shown([message]))
        shown.received([])
        #expect(shown == .unavailable(.gone))
    }

    @Test func aFetchThatLeavesTheStoreEmptyEndsTheWait() {
        var content = ConversationContent.loading
        content.fetched(.done(stored: false))
        #expect(content == .unavailable(.gone), "not a blank screen for ever")
        var shown = ConversationContent.shown([message])
        shown.fetched(.done(stored: false))
        #expect(shown == .shown([message]), "the store's own word decides once it has spoken")
    }

    @Test func oneThatLeavesTheDeviceWhileReadIsGone() {
        var content = ConversationContent.shown([message])
        content.received([])
        #expect(content == .unavailable(.gone))
        #expect(content.messages.isEmpty)
    }

    @Test func aFailedFetchSaysSoOnlyWithNothingToShow() {
        var content = ConversationContent.loading
        content.fetched(.failed)
        #expect(content == .unavailable(.unreachable))
        content.refetching()
        #expect(content == .loading, "Try Again")
        var shown = ConversationContent.shown([message])
        shown.fetched(.failed)
        #expect(shown == .shown([message]), "the messages on the device stay")
    }

    @Test func messagesArrivingLaterShowAfterAll() {
        var content = ConversationContent.unavailable(.unreachable)
        content.received([message])
        #expect(content == .shown([message]))
    }
}
