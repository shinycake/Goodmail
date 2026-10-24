import Foundation
import MailCore
import Testing

@testable import MailUI

@MainActor
struct ComposeViewModelTests {
    private let account = AccountID(rawValue: "a")

    private func model(_ draft: Draft, sent: @escaping (Draft) -> Void = { _ in }) -> ComposeViewModel {
        ComposeViewModel(draft: draft, accountEmail: "me@example.com", send: sent)
    }

    @Test func suggestsForTheRecipientBeingTypedOnly() {
        let dana = Contact(name: "Dana Levi", address: "dana@example.com")
        let daniel = Contact(name: "Daniel, Jr.", address: "dan@example.com")
        var asked: [String] = []
        let model = ComposeViewModel(
            draft: Draft(accountID: account), accountEmail: "me@example.com",
            suggest: {
                asked.append($0)
                return [dana, daniel]
            }, send: { _ in })
        #expect(model.suggestions(for: "Dana Levi <dana@example.com>, da").map(\.address) == ["dan@example.com"])
        #expect(model.suggestions(for: "\"Levi, Dana\" <x@example.com>, ").isEmpty, "nothing typed yet")
        #expect(asked == ["da"])
        #expect(
            ComposeViewModel.completing("dana@example.com, da", with: daniel)
                == "dana@example.com, \"Daniel, Jr.\" <dan@example.com>, ")
        #expect(ComposeViewModel.completing("da", with: dana) == "Dana Levi <dana@example.com>, ")
    }

    @Test func filesGoWithTheMessageWithinGmailsLimit() {
        var sent: Draft?
        let model = model(
            Draft(accountID: account, to: [Contact(name: nil, address: "dana@example.com")]), sent: { sent = $0 })
        let photo = DraftAttachment(filename: "a.jpg", mimeType: "image/jpeg", data: Data(count: 10_000_000))
        let video = DraftAttachment(filename: "b.mov", mimeType: "video/quicktime", data: Data(count: 10_000_000))
        #expect(model.attach(photo))
        #expect(model.hasChanges(body: MessageBody(plain: "")), "an added file counts as a change")
        #expect(!model.attach(video), "together they'd pass 25 MB once encoded")
        model.send(body: MessageBody(plain: "Here"))
        #expect(sent?.attachments == [photo])
        model.removeAttachment(photo.id)
        #expect(model.attachments.isEmpty)
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

    @Test func aNewDraftStartsWithTheSignatureAndClosesQuietly() {
        let model = ComposeViewModel(
            draft: Draft(accountID: account), accountEmail: "me@example.com", signature: "Dana\nGoodmail",
            send: { _ in })
        #expect(model.draft.body.plain == "\n\n-- \nDana\nGoodmail")
        #expect(!model.isRestored)
        #expect(!model.hasChanges(body: model.draft.body))
        #expect(model.hasChanges(body: MessageBody(plain: "Hi\n\n-- \nDana\nGoodmail")))
    }

    @Test func aRestoredDraftKeepsItsOwnSignature() {
        let body = MessageBody(html: "<div>Hi</div>", plain: "Hi")
        let model = ComposeViewModel(
            draft: Draft(accountID: account, body: body), accountEmail: "me@example.com", signature: "Dana",
            send: { _ in })
        #expect(model.draft.body == body)
    }

    @Test func aDraftFromDraftsClosesQuietlyAndSavesOrDeletesItsCopy() {
        var saved: Draft?
        var deleted: Draft?
        let draft = Draft(
            accountID: account, subject: "Plan", body: MessageBody(html: "<div>Hi</div>", plain: "Hi"),
            savedDraft: Message.ID(accountID: account, messageID: "d1"))
        let model = ComposeViewModel(
            draft: draft, accountEmail: "me@example.com", signature: "Dana", saveDraft: { saved = $0 },
            deleteDraft: { deleted = $0 }, send: { _ in })
        #expect(model.draft.body.plain == "Hi", "no second signature")
        #expect(!model.hasChanges(body: draft.body))
        #expect(model.canSaveDraft)
        model.saveDraft(body: MessageBody(plain: "Hi there"))
        #expect(saved?.body.plain == "Hi there")
        #expect(saved?.savedDraft == draft.savedDraft)
        model.deleteDraft()
        #expect(deleted?.savedDraft == draft.savedDraft)
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
