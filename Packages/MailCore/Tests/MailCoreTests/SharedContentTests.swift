import Foundation
import MailCore
import Testing

/// What another app shares becomes the start of a new message: a page's title its subject, its text and links the
/// body, each link once.
struct SharedContentTests {
    private let page = URL(string: "https://example.com/story")!

    @Test func aPageSharedFromSafariBecomesItsTitleAndLink() {
        let shared = SharedContent(title: "  A good story\n", links: [page])

        #expect(shared.subject == "A good story")
        #expect(shared.body == "https://example.com/story")
    }

    @Test func textComesBeforeLinksEachInItsOwnParagraph() {
        let shared = SharedContent(texts: ["Look at this", " "], links: [page, URL(string: "https://example.com/b")!])

        #expect(shared.subject.isEmpty)
        #expect(shared.body == "Look at this\n\nhttps://example.com/story\n\nhttps://example.com/b")
    }

    @Test func aLinkTheTextAlreadyHoldsOrThatCameTwiceShowsOnce() {
        let shared = SharedContent(texts: ["Look: https://example.com/story"], links: [page, page])

        #expect(shared.body == "Look: https://example.com/story")
        #expect(SharedContent(links: [page, page]).body == "https://example.com/story")
    }

    @Test func onlyAFileStillMakesAMessage() {
        let file = DraftAttachment(filename: "a.pdf", mimeType: "application/pdf", data: Data([1]))

        #expect(!SharedContent(files: [file]).isEmpty)
        #expect(SharedContent(title: " ", texts: [""]).isEmpty)
    }
}
