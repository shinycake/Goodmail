import MailCore
import Testing

@testable import MailUI

@MainActor
struct ComposeViewModelTests {
    private let account = AccountID(rawValue: "a")

    private func model(_ draft: Draft, sent: @escaping (Draft) -> Void = { _ in }) -> ComposeViewModel {
        ComposeViewModel(draft: draft, accountEmail: "me@example.com", send: sent)
    }

    @Test func anUntouchedMessageClosesQuietly() {
        let reply = Draft(
            accountID: account, to: [Contact(name: "Dana", address: "dana@example.com")], subject: "Re: Lunch")
        #expect(!model(reply).hasChanges(body: MessageBody(html: "<div dir=\"auto\"><br></div>", plain: "")))
    }

    @Test func typingOrAddressingCountsAsAChange() {
        let model = model(Draft(accountID: account))
        #expect(model.hasChanges(body: MessageBody(plain: "Hi")))
        model.toText = "dana@example.com"
        #expect(model.hasChanges(body: MessageBody(plain: "")))
    }

    @Test func aRestoredDraftAlwaysAsksBeforeClosing() {
        var draft = Draft(accountID: account, to: [Contact(name: nil, address: "dana@example.com")])
        draft.body = MessageBody(html: "<div dir=\"auto\">Hi</div>", plain: "Hi")
        #expect(model(draft).hasChanges(body: draft.body), "Undo brought it back; closing would lose it")
    }

    @Test func sendsOnlyToAddresses() {
        var sent: [Draft] = []
        let model = model(Draft(accountID: account)) { sent.append($0) }
        model.toText = "dana"
        #expect(!model.canSend)
        model.send(body: MessageBody(plain: "Hi"))
        #expect(sent.isEmpty)

        model.toText = "Dana Levi <dana@example.com>, avi@example.com"
        #expect(model.canSend)
        model.send(body: MessageBody(plain: "Hi"))
        #expect(sent.first?.to.map(\.address) == ["dana@example.com", "avi@example.com"])
        #expect(sent.first?.body.plain == "Hi")
    }
}
