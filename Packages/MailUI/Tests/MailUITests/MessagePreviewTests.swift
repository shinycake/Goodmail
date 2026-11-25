import Foundation
import MailCore
import Testing

@testable import MailUI

/// A body's web view can take seconds to start, so the card shows the message's new words until it lays out.
@MainActor
struct MessagePreviewTests {
    private func message(_ id: String, plain: String) -> Message {
        Message(
            id: Message.ID(accountID: AccountID(rawValue: "a"), messageID: id), threadID: "t",
            from: Contact(name: "Dana", address: "dana@example.com"), subject: "Plan",
            date: Date(timeIntervalSince1970: 1_800_000_000), labelIDs: ["INBOX"], body: MessageBody(plain: plain))
    }

    private func webView() -> MessageWebView {
        MessageWebView { _, _ in throw ProviderError.notFound }
    }

    /// The page in the view until this message's commits is the one before it, whose height isn't this message's
    /// (`BodyLoadTests` follows the load through).
    @Test func theNewWordsShowUntilTheBodysOwnPageHasItsHeight() {
        let view = webView()
        var laidOut = 0
        view.onLayout = { _, _ in laidOut += 1 }
        view.show(
            .init(
                message: message("m", plain: "Sounds good, see you then\n\nOn Monday, Dana wrote:\n> Lunch?"),
                allowsRemoteContent: false))
        #expect(view.previewText == "Sounds good, see you then")

        view.handle(["height": 86.0, "hasRemote": false])
        #expect(view.previewText == "Sounds good, see you then")
        #expect(laidOut == 0)
    }

    @Test func anotherMessageStartsFromItsWords() {
        let view = webView()
        view.show(.init(message: message("m", plain: "Sounds good"), allowsRemoteContent: false))
        view.show(.init(message: message("n", plain: "Another one"), allowsRemoteContent: true))
        #expect(view.previewText == "Another one")
    }

    @Test func aBodyWithNoWordsShowsNoPreview() {
        let view = webView()
        view.show(.init(message: message("m", plain: "> Lunch?"), allowsRemoteContent: false))
        #expect(view.previewText == nil)
    }
}
