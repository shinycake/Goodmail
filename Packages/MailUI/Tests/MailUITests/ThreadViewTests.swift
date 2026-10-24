import Foundation
import MailCore
import Testing
import UIKit

@testable import MailUI

struct MessageDocumentTests {
    @Test func plainTextIsEscapedAndQuotesNestByDepth() {
        let html = MessageDocument.plainToHTML("Hi <team>\n\n> On Monday:\n>> Ship it?\nThanks")
        #expect(html.contains(#"<div dir="auto">Hi &lt;team&gt;</div><br>"#))
        #expect(html.contains(#"<blockquote class="goodmail-quote"><div dir="auto">On Monday:</div>"#))
        #expect(
            html.contains(
                #"<blockquote class="goodmail-quote"><div dir="auto">Ship it?</div></blockquote></blockquote>"#))
        #expect(html.hasSuffix(#"<div dir="auto">Thanks</div>"#))
    }

    @Test func ourStylesGoFirstInTheSendersHead() {
        let html = MessageDocument.html(
            for: MessageBody(html: "<html><head><style>p{}</style></head><body>x</body></html>"))
        let ours = html.range(of: "-webkit-text-size-adjust")!
        let theirs = html.range(of: "p{}")!
        #expect(ours.lowerBound < theirs.lowerBound)
    }

    @Test func bareFragmentsGetADocument() {
        let html = MessageDocument.html(for: MessageBody(html: "<p>Hello</p>"))
        #expect(html.hasPrefix("<!doctype html><html><head>"))
        #expect(html.hasSuffix("<body><p>Hello</p></body></html>"))
    }
}

@MainActor
struct ThreadViewModelTests {
    private let account = AccountID(rawValue: "a")

    private func message(_ id: String, unread: Bool, minutes: Double) -> Message {
        var labels: Set<String> = ["INBOX"]
        if unread { labels.insert("UNREAD") }
        return Message(
            id: Message.ID(accountID: account, messageID: id), threadID: "t",
            from: Contact(name: "Dana", address: "dana@example.com"), subject: "Plan",
            date: Date(timeIntervalSince1970: minutes * 60), labelIDs: labels, body: MessageBody(plain: id))
    }

    @Test func unreadMessagesAndTheNewestOpenAsCards() {
        let messages = [
            message("1", unread: false, minutes: 1), message("2", unread: true, minutes: 2),
            message("3", unread: false, minutes: 3), message("4", unread: false, minutes: 4),
        ]
        #expect(ThreadViewModel.initiallyExpanded(messages) == [messages[1].id, messages[3].id])
    }

    @Test func theLastOpenCardCannotBeClosed() {
        let messages = [message("1", unread: false, minutes: 1)]
        let model = ThreadViewModel(
            thread: ThreadSummary(
                id: .init(accountID: account, threadID: "t"), subject: "Plan", snippet: "",
                sender: messages[0].from, date: .now, isUnread: false, messageCount: 1, labelIDs: []),
            accountEmail: "me@example.com", accountColor: .blue,
            messages: { AsyncThrowingStream { $0.finish() } }, load: {}, attachmentData: { _, _ in Data() })
        model.toggle(messages[0].id)
        #expect(model.expanded == [messages[0].id])
        model.toggle(messages[0].id)
        #expect(model.expanded == [messages[0].id], "a thread always shows at least one card")
    }

    @Test func aTrailingDraftIsEditedAndRepliesAnswerTheLastSentMessage() async {
        var draft = message("2", unread: false, minutes: 2)
        draft.labelIDs = [SystemLabel.draft]
        let messages = [message("1", unread: false, minutes: 1), draft]
        var routes: [Route] = []
        let model = ThreadViewModel(
            thread: ThreadSummary(
                id: .init(accountID: account, threadID: "t"), subject: "Plan", snippet: "",
                sender: messages[0].from, date: .now, isUnread: false, messageCount: 2, labelIDs: []),
            accountEmail: "me@example.com", accountColor: .blue,
            messages: {
                AsyncThrowingStream {
                    $0.yield(messages)
                    $0.finish()
                }
            }, load: {}, attachmentData: { _, _ in Data() }, navigate: { routes.append($0) })
        await model.observe()
        #expect(model.draft?.id == draft.id)

        model.editDraft()
        model.reply(all: false)
        guard case .compose(let edited) = routes.first, case .compose(let reply) = routes.last else {
            Issue.record("both should open the composer")
            return
        }
        #expect(edited.savedDraft == draft.id)
        #expect(edited.body.plain == "2")
        #expect(reply.savedDraft == nil)
        #expect(reply.to.map(\.address) == ["dana@example.com"])
    }
}

@MainActor
struct AttachmentFileTests {
    @Test func attachmentsDownloadOnceAndKeepTheirName() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let account = AccountID(rawValue: "a")
        var fetches = 0
        let model = ThreadViewModel(
            thread: ThreadSummary(
                id: .init(accountID: account, threadID: "t"), subject: "Quote", snippet: "",
                sender: Contact(name: nil, address: "a@example.com"), date: .now, isUnread: false, messageCount: 1,
                labelIDs: []),
            accountEmail: "me@example.com", accountColor: .blue,
            messages: { AsyncThrowingStream { $0.finish() } }, load: {},
            attachmentData: { _, _ in
                fetches += 1
                return Data("%PDF".utf8)
            },
            attachmentsDirectory: directory)
        let attachment = Attachment(id: "1", filename: "../Quote 2026.pdf", mimeType: "application/pdf", size: 4)
        let message = Message.ID(accountID: account, messageID: "m")
        let first = try await model.file(for: attachment, in: message)
        let second = try await model.file(for: attachment, in: message)
        #expect(first == second)
        #expect(fetches == 1)
        #expect(first.lastPathComponent == "-Quote 2026.pdf")
        #expect(first.path().hasPrefix(directory.path()))
        #expect(try Data(contentsOf: first) == Data("%PDF".utf8))
    }

    @Test func inlineImagesTheBodyPlacesAreNotListed() {
        let message = Message(
            id: .init(accountID: AccountID(rawValue: "a"), messageID: "m"), threadID: "t",
            from: Contact(name: nil, address: "a@example.com"), subject: "", date: .now, body: MessageBody(),
            attachments: [
                Attachment(
                    id: "1", filename: "logo.png", mimeType: "image/png", size: 1, contentID: "logo", isInline: true),
                Attachment(id: "2", filename: "quote.pdf", mimeType: "application/pdf", size: 1),
            ])
        #expect(AttachmentListView.listed(in: message).map(\.id) == ["2"])
        #expect(AttachmentListView.symbol(for: "application/pdf") == "doc.richtext")
    }
}

struct RichTextSerializerTests {
    @Test func paragraphsAreAutoDirectionBlocksWithTheirStyles() {
        let body = UIFont.preferredFont(forTextStyle: .body)
        let bold = UIFont(descriptor: body.fontDescriptor.withSymbolicTraits(.traitBold)!, size: 0)
        let text = NSMutableAttributedString(string: "Hi <Dana>,\n\nשלום ", attributes: [.font: body])
        text.append(NSAttributedString(string: "bold", attributes: [.font: bold]))
        text.append(
            NSAttributedString(
                string: " link", attributes: [.font: body, .link: URL(string: "https://example.com/?a=1&b=2")!]))

        #expect(
            RichTextSerializer.html(from: text)
                == "<div dir=\"auto\">Hi &lt;Dana&gt;,</div><div dir=\"auto\"><br></div>"
                + "<div dir=\"auto\">שלום <b>bold</b><a href=\"https://example.com/?a=1&amp;b=2\"> link</a></div>")
        #expect(RichTextSerializer.body(from: text).plain == "Hi <Dana>,\n\nשלום bold link")
    }

    @Test func writtenHTMLReadsBackTheSame() throws {
        let font = UIFont.systemFont(ofSize: 17)
        let bold = try #require(font.fontDescriptor.withSymbolicTraits(.traitBold))
        let text = NSMutableAttributedString(string: "Hi <Dana> & co,\n\n", attributes: [.font: font])
        text.append(NSAttributedString(string: "bold", attributes: [.font: UIFont(descriptor: bold, size: 0)]))
        text.append(
            NSAttributedString(
                string: " link\n", attributes: [.font: font, .link: URL(string: "https://example.com/?a=1&b=2")!]))
        let html = RichTextSerializer.html(from: text)
        let read = RichTextSerializer.attributedText(from: MessageBody(html: html, plain: text.string), font: font)
        #expect(read.string == text.string)
        #expect(RichTextSerializer.html(from: read) == html)
    }

    @Test func emptyAndTrailingLinesSurvive() {
        #expect(RichTextSerializer.html(from: NSAttributedString(string: "")) == "<div dir=\"auto\"><br></div>")
        #expect(
            RichTextSerializer.html(from: NSAttributedString(string: "a\n"))
                == "<div dir=\"auto\">a</div><div dir=\"auto\"><br></div>")
    }
}
