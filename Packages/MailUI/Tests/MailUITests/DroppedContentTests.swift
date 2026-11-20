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
        #expect(!SharedItems.holdsWords(NSItemProvider(object: URL(fileURLWithPath: "/tmp/report.pdf") as NSURL)))
    }

    @Test(arguments: [
        ("photo", "IMG_1.jpeg", "photo.jpeg"),
        ("photo.JPEG", "IMG_1.jpeg", "photo.JPEG"),
        ("Q3/Q4 plan", "x.pdf", "Q3-Q4 plan.pdf"),
        ("", "IMG_1.jpeg", "IMG_1.jpeg"),
    ])
    func aFileKeepsTheNameItsAppSuggests(suggested: String, file: String, expected: String) {
        let url = URL(fileURLWithPath: "/tmp/\(file)")
        #expect(SharedItems.filename(suggested, for: url, type: .data) == expected)
    }

    @Test(
        arguments: [
            ("dear", "o", "w", " dear "),
            ("dear", nil, nil, "dear"),
            ("dear", " ", "\n", "dear"),
            ("שלום", "a", nil, " שלום"),
            (" dear", "o", "w", " dear "),
        ] as [(String, Character?, Character?, String)])
    func droppedWordsKeepApartFromTheWordsAround(words: String, previous: Character?, next: Character?, spaced: String)
    {
        #expect(DroppedWords.spaced(words, after: previous, before: next) == spaced)
    }

    @Test func filesStayUnderTheLimit() {
        var files = [
            DraftAttachment(
                filename: "a.mov", mimeType: "video/quicktime", data: Data(count: ComposeViewModel.attachmentLimit - 5))
        ]
        let tooBig = files.attachIfRoom(DraftAttachment(filename: "b", mimeType: "image/png", data: Data(count: 6)))
        let fitting = files.attachIfRoom(DraftAttachment(filename: "c", mimeType: "image/png", data: Data(count: 5)))
        #expect(!tooBig)
        #expect(fitting)
        #expect(files.map(\.filename) == ["a.mov", "c"])
        #expect(files.room == 0)
    }

    @Test func aDropWithNoMessageBeingWrittenStartsOneOnlyWithAnAccount() {
        let shelf = DraftShelfViewController()
        var started: [SharedContent] = []
        shelf.newMessageHolding = { started.append($0.content) }
        #expect(!shelf.takesDrops)
        shelf.canStartMessage = { true }
        #expect(shelf.takesDrops)
        shelf.dropped(SharedItems.Loaded(content: SharedContent(texts: ["Hi"]), leftOutFiles: false))
        #expect(started == [SharedContent(texts: ["Hi"])])
    }

    @Test func aPictureFromAPageIsAttachedNotLinked() {
        let provider = NSItemProvider(object: URL(string: "https://example.com/cat.jpeg")! as NSURL)
        provider.registerDataRepresentation(for: .jpeg) { load in
            load(Data(count: 3), nil)
            return nil
        }
        #expect(!SharedItems.holdsWords(provider))
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

    @Test func aDropReadsEveryItemAtOnceAndKeepsFilesTogetherUnderTheLimit() async {
        let started = SharedItems.start(
            SharedItems.Request(providers: [
                Self.file(named: "one", type: .jpeg, size: 30),
                NSItemProvider(object: "Hi" as NSString),
                Self.file(named: "two", type: .jpeg, size: 30),
            ]),
            limit: 50)
        let loaded = await started.loaded()
        #expect(loaded.content.body == "Hi")
        #expect(loaded.content.files.map(\.filename) == ["one.jpeg"])
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
            SharedItems.Loaded(content: SharedContent(texts: ["dear"], files: [photo]), leftOutFiles: false))
        #expect(composer.bodyView.text == "Hello dear world")
        #expect(composer.viewModel.attachments.map(\.filename) == ["photo.jpeg"])
    }

    @Test func droppedWordsChosenAsAQuoteGoOnLinesOfTheirOwn() throws {
        let composer = composer(body: "Before after")
        composer.bodyView.selectedRange = NSRange(location: 7, length: 0)
        let landed = composer.bodyView.writeDropped("dear")
        composer.quoteDropped(landed)
        #expect(composer.bodyView.text == "Before\ndear\nafter")
        let html = try #require(composer.body.html)
        #expect(html.components(separatedBy: "<blockquote").count == 2)
        #expect(html.contains("dear"))
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
