import MailCore
import Testing
import UIKit
import UniformTypeIdentifiers

@testable import MailUI

/// What other apps drop or paste: read the way a share is, and put into the message where the writer is.
@MainActor
struct DroppedContentTests {
    private static func file(named name: String, type: UTType, size: Int) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(for: type) { load in
            load(Data(count: size), nil)
            return nil
        }
        provider.suggestedName = name
        return provider
    }

    @Test func linksAndWrittenWordsGoInTheTextWhileNamedFilesAreAttached() {
        #expect(SharedItems.holdsWords(NSItemProvider(object: URL(string: "https://example.com/a")! as NSURL)))
        #expect(SharedItems.holdsWords(NSItemProvider(object: "שלום" as NSString)))
        #expect(!SharedItems.holdsWords(Self.file(named: "notes", type: .plainText, size: 3)))
        #expect(!SharedItems.holdsWords(Self.file(named: "photo", type: .jpeg, size: 3)))
    }

    @Test func aDropIsReadAsAShareIs() async {
        let loaded = await SharedItems.load(
            SharedItems.Request(providers: [
                NSItemProvider(object: "Look at this" as NSString),
                NSItemProvider(object: URL(string: "https://example.com/a")! as NSURL),
                Self.file(named: "photo", type: .jpeg, size: 10),
                Self.file(named: "film", type: .mpeg4Movie, size: 100),
            ]),
            limit: 50)
        #expect(loaded.content.body == "Look at this\n\nhttps://example.com/a")
        #expect(loaded.content.files.map(\.filename) == ["photo.jpeg"])
        #expect(loaded.leftOutFiles)
    }

    private func composer(body: String, attachments: [DraftAttachment] = []) -> ComposeViewController {
        let composer = ComposeViewController(
            viewModel: ComposeViewModel(
                draft: Draft(
                    accountID: AccountID(rawValue: "a"), body: MessageBody(html: nil, plain: body),
                    attachments: attachments),
                accountEmail: "me@example.com", send: { _, _ in }))
        composer.loadViewIfNeeded()
        return composer
    }

    @Test func wordsLandAtTheCaretAndFilesAreAttached() {
        let composer = composer(body: "Hello world")
        composer.bodyView.selectedRange = NSRange(location: 6, length: 0)
        let photo = DraftAttachment(filename: "photo.jpeg", mimeType: "image/jpeg", data: Data(count: 10))
        composer.receive(
            SharedItems.Loaded(content: SharedContent(texts: ["dear "], files: [photo]), leftOutFiles: false))
        #expect(composer.bodyView.text == "Hello dear world")
        #expect(composer.viewModel.attachments.map(\.filename) == ["photo.jpeg"])
    }

    @Test func aTitleBecomesTheSubjectOnlyWhenThereIsNone() {
        let composer = composer(body: "Hi")
        let page = SharedContent(title: "A page", links: [URL(string: "https://example.com")!])
        composer.receive(SharedItems.Loaded(content: page, leftOutFiles: false))
        #expect(composer.viewModel.subject == "A page")
        composer.receive(
            SharedItems.Loaded(content: SharedContent(title: "Another page"), leftOutFiles: false))
        #expect(composer.viewModel.subject == "A page")
    }

    @Test func aFileThatWouldPassTheLimitStaysOut() {
        let big = DraftAttachment(
            filename: "big.mov", mimeType: "video/quicktime", data: Data(count: ComposeViewModel.attachmentLimit - 5))
        let composer = composer(body: "Hi", attachments: [big])
        let photo = DraftAttachment(filename: "photo.jpeg", mimeType: "image/jpeg", data: Data(count: 10))
        composer.receive(SharedItems.Loaded(content: SharedContent(files: [photo]), leftOutFiles: false))
        #expect(composer.viewModel.attachments.map(\.filename) == ["big.mov"])
        #expect(composer.viewModel.attachmentRoom == 5)
    }
}
