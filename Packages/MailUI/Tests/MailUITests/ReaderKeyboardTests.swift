import Foundation
import MailCore
import Testing
import UIKit

@testable import MailUI

// They follow the store's streams, so one that never finishes fails the test instead of hanging the run.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct ReaderKeyboardTests {
    private let account = AccountID(rawValue: "a")
    private let dana = Contact(name: "Dana", address: "dana@example.com")

    private func reader(
        in mailbox: Mailbox = .inbox, labels: Set<String> = [SystemLabel.inbox], actions: MailActions? = nil,
        navigate: @escaping (Route) -> Void = { _ in }
    ) async -> ThreadViewController {
        let message = Message(
            id: Message.ID(accountID: account, messageID: "1"), threadID: "t", from: dana, subject: "Plan",
            date: Date(timeIntervalSince1970: 60), labelIDs: labels, body: MessageBody(plain: "Lunch?"))
        let model = ThreadViewModel(
            thread: ThreadSummary(
                id: .init(accountID: account, threadID: "t"), subject: "Plan", snippet: "", sender: dana,
                date: .now, isUnread: false, messageCount: 1, labelIDs: labels),
            mailbox: mailbox, accountEmail: "me@example.com", accountColor: .blue,
            messages: {
                AsyncThrowingStream {
                    $0.yield([message])
                    $0.finish()
                }
            }, load: {}, attachmentData: { _, _ in Data() }, source: { _ in Data() }, actions: actions,
            navigate: navigate, layout: .chat)
        await model.observe()
        return ThreadViewController(viewModel: model, openURL: { _ in })
    }

    private func type(_ text: String, into bar: ChatComposerBar) throws {
        let field = try #require(bar.descendants().compactMap { $0 as? UITextView }.first)
        field.text = text
        bar.textViewDidChange(field)
    }

    @Test func `the chat's field sends what is typed, as its Send button does`() async throws {
        let reader = await reader()
        var sent: [String] = []
        reader.composer.onSend = { text, _, _ in sent.append(text) }
        #expect(reader.composer.unsent == nil)
        try type("  On my way ", into: reader.composer)
        #expect(reader.composer.unsent?.text == "On my way")
        reader.composer.send()
        #expect(sent == ["On my way"])
        #expect(reader.composer.unsent == nil, "the field empties once it is sent")
    }

    @Test func `a reply typed and not sent goes to Drafts as the reader goes`() async throws {
        let store = OutgoingQueue()
        let actions = MailActions(commands: MailCommands(store: store, replay: { _ in }))
        let reader = await reader(actions: actions)
        try type("See you there", into: reader.composer)

        reader.leave()
        reader.leave()
        await actions.settled()
        #expect(store.messages.map(\.purpose) == [.saveDraft], "kept once")
        #expect(store.messages.first?.draft.body.plain == "See you there")
        #expect(store.messages.first?.draft.to == [dana])
    }

    @Test func `a reader left with nothing typed keeps no draft`() async {
        let store = OutgoingQueue()
        let actions = MailActions(commands: MailCommands(store: store, replay: { _ in }))
        let reader = await reader(actions: actions)
        reader.leave()
        await actions.settled()
        #expect(store.messages.isEmpty)
    }

    @Test(arguments: [
        (Mailbox.spam, Set([SystemLabel.spam]), ThreadAction.moveToInbox),
        (.trash, Set([SystemLabel.trash]), .untrash),
        (.inbox, Set([SystemLabel.inbox]), .archive),
    ])
    func `Archive does what the mailbox's archive does`(
        mailbox: Mailbox, labels: Set<String>, action: ThreadAction
    ) async throws {
        let actions = MailActions(commands: MailCommands(store: NoStore(), replay: { _ in }))
        var changes: [MailChange] = []
        actions.changed = { changes.append($0) }
        let reader = await reader(in: mailbox, labels: labels, actions: actions)
        guard case .ready(let perform, let title, _) = reader.answer(to: .archive) else {
            Issue.record("Archive should be ready in \(mailbox)")
            return
        }
        #expect(title == action.title)
        perform()
        #expect(changes == [MailChange(.action(action), on: [reader.viewModel.thread.id])])
        await actions.settled()
    }

    @Test func `Archive is dimmed for a conversation already out of the Inbox`() async {
        let reader = await reader(in: Mailbox(labelID: "Label_1"), labels: ["Label_1"])
        guard case .unavailable = reader.answer(to: .archive) else {
            Issue.record("Archive should be dimmed")
            return
        }
    }

    @Test(arguments: [(Mailbox.spam, SystemLabel.spam), (.trash, SystemLabel.trash)])
    func `Snooze is dimmed in Spam and Trash`(mailbox: Mailbox, label: String) async {
        let reader = await reader(in: mailbox, labels: [label])
        guard case .unavailable = reader.answer(to: .snooze) else {
            Issue.record("Snooze should be dimmed in \(mailbox)")
            return
        }
    }

    @Test func `a mailto link in a message writes a new message here`() async throws {
        var routes: [Route] = []
        let reader = await reader(navigate: { routes.append($0) })
        var opened: [URL] = []
        let mailto = try #require(URL(string: "mailto:avi@example.com?subject=Hi"))
        let web = try #require(URL(string: "https://example.com"))
        reader.viewModel.open(mailto) { opened.append($0) }
        reader.viewModel.open(web) { opened.append($0) }
        let draft = try #require(Draft(mailto: mailto, from: account))
        guard case .compose(let written) = routes.first else {
            Issue.record("Expected the composer, got \(routes)")
            return
        }
        #expect(written.to == draft.to && written.subject == "Hi" && written.accountID == account)
        #expect(opened == [web])
    }

    @Test(arguments: ["mailto:avi@example.com", "MAILTO:avi@example.com?cc=dana@example.com"])
    func `mailto links compose`(_ link: String) throws {
        let url = try #require(URL(string: link))
        guard case .compose(let draft) = MessageLink(url, account: account) else {
            Issue.record("Expected a new message for \(link)")
            return
        }
        #expect(draft.to.map(\.address) == ["avi@example.com"])
    }

    @Test(arguments: ["https://example.com/a", "tel:+15555550100", "sms:+15555550100"])
    func `other links open outside`(_ link: String) throws {
        let url = try #require(URL(string: link))
        #expect(MessageLink(url, account: account) == .outside(url))
    }
}

extension UIView {
    fileprivate func descendants() -> [UIView] {
        subviews + subviews.flatMap { $0.descendants() }
    }
}
