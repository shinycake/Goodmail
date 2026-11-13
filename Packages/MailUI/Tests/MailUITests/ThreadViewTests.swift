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
            mailbox: .inbox,
            accountEmail: "me@example.com", accountColor: .blue, accountService: .gmail,
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
            mailbox: .inbox,
            accountEmail: "me@example.com", accountColor: .blue, accountService: .gmail,
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

extension ThreadViewModelTests {
    @Test func muteIsOfferedFromTheThreadsCurrentLabelsAndClosesTheReader() async {
        var inbox = message("1", unread: false, minutes: 1)
        inbox.labelIDs = ["INBOX"]
        var closes = 0
        let model = ThreadViewModel(
            thread: ThreadSummary(
                id: .init(accountID: account, threadID: "t"), subject: "Plan", snippet: "",
                sender: inbox.from, date: .now, isUnread: false, messageCount: 1, labelIDs: ["INBOX"]),
            mailbox: .inbox,
            accountEmail: "me@example.com", accountColor: .blue, accountService: .gmail,
            messages: {
                AsyncThrowingStream {
                    $0.yield([inbox])
                    $0.finish()
                }
            }, load: {}, attachmentData: { _, _ in Data() }, close: { closes += 1 })
        #expect(model.muteAction == .mute, "before the messages load, the summary's labels decide")
        await model.observe()
        #expect(model.muteAction == .mute)

        model.perform(.mute)
        model.perform(.mute)
        #expect(closes == 1, "muting takes the thread out of the way, once")
    }

    @Test func aMutedThreadOffersUnmuteAndStaysOpenAfterIt() async {
        var muted = message("1", unread: false, minutes: 1)
        muted.labelIDs = ["MUTED"]
        var closes = 0
        let model = ThreadViewModel(
            thread: ThreadSummary(
                id: .init(accountID: account, threadID: "t"), subject: "Plan", snippet: "",
                sender: muted.from, date: .now, isUnread: false, messageCount: 1, labelIDs: ["MUTED"]),
            mailbox: .allMail,
            accountEmail: "me@example.com", accountColor: .blue, accountService: .gmail,
            messages: {
                AsyncThrowingStream {
                    $0.yield([muted])
                    $0.finish()
                }
            }, load: {}, attachmentData: { _, _ in Data() }, close: { closes += 1 })
        await model.observe()
        #expect(model.muteAction == .unmute)
        model.perform(.unmute)
        #expect(closes == 0)
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
            mailbox: .inbox,
            accountEmail: "me@example.com", accountColor: .blue, accountService: .gmail,
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

    @Test func openingACachedAttachmentMarksItRecentlyUsed() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let account = AccountID(rawValue: "a")
        let today = Date(timeIntervalSince1970: 1_800_000_000)
        let model = ThreadViewModel(
            thread: ThreadSummary(
                id: .init(accountID: account, threadID: "t"), subject: "Quote", snippet: "",
                sender: Contact(name: nil, address: "a@example.com"), date: today, isUnread: false, messageCount: 1,
                labelIDs: []),
            mailbox: .inbox,
            accountEmail: "me@example.com", accountColor: .blue, accountService: .gmail,
            messages: { AsyncThrowingStream { $0.finish() } }, load: {},
            attachmentData: { _, _ in Data("%PDF".utf8) },
            attachmentsDirectory: directory,
            now: { today })
        let attachment = Attachment(id: "1", filename: "Quote.pdf", mimeType: "application/pdf", size: 4)
        let message = Message.ID(accountID: account, messageID: "m")
        let url = try await model.file(for: attachment, in: message)
        let path = url.path(percentEncoded: false)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 0)], ofItemAtPath: path)

        _ = try await model.file(for: attachment, in: message)
        #expect(try FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date == today)
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
