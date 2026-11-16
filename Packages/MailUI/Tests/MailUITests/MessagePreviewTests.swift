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

    @Test func theNewWordsShowUntilTheBodyHasItsHeight() {
        let view = webView()
        view.show(
            .init(
                message: message("m", plain: "Sounds good, see you then\n\nOn Monday, Dana wrote:\n> Lunch?"),
                allowsRemoteContent: false))
        #expect(view.previewText == "Sounds good, see you then")

        view.handle(["height": 86.0, "hasRemote": false])
        #expect(view.previewText == nil)
    }

    @Test func loadingRemoteImagesKeepsTheBodyThatShows() {
        let view = webView()
        let shown = message("m", plain: "Sounds good")
        view.show(.init(message: shown, allowsRemoteContent: false))
        view.handle(["height": 24.0, "hasRemote": true])

        view.show(.init(message: shown, allowsRemoteContent: true))
        #expect(view.previewText == nil)

        view.show(.init(message: message("n", plain: "Another one"), allowsRemoteContent: true))
        #expect(view.previewText == "Another one")
    }

    @Test func aBodyWithNoWordsShowsNoPreview() {
        let view = webView()
        view.show(.init(message: message("m", plain: "> Lunch?"), allowsRemoteContent: false))
        #expect(view.previewText == nil)
    }
}
