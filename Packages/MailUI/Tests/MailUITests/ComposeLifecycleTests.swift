import Foundation
import MailCore
import Testing
import UIKit

@testable import MailUI

/// A message is written until it ends one way, sent, saved, deleted, closed or moved to a window of its own. After that
/// nothing ends it again, even while its card is still on screen sliding away.
@MainActor
struct ComposeLifecycleTests {
    private let account = AccountID(rawValue: "a")

    /// What a message did, in order.
    @MainActor
    final class Outcomes {
        var log: [String] = []
    }

    private func model(_ outcomes: Outcomes, draft: Draft? = nil) -> ComposeViewModel {
        ComposeViewModel(
            draft: draft ?? Draft(accountID: account, to: [Contact(name: nil, address: "dana@example.com")]),
            accountEmail: "me@example.com", saveDraft: { _, wait in outcomes.log.append("save \(wait)") },
            deleteDraft: { _ in outcomes.log.append("delete") }, autosavePause: .zero,
            send: { _, _ in outcomes.log.append("send") })
    }

    @Test func aMessageSentOnceIsNotSentDeletedOrSavedAgain() {
        let outcomes = Outcomes()
        let model = model(outcomes)
        #expect(model.send(body: MessageBody(plain: "Hi")))
        #expect(!model.send(body: MessageBody(plain: "Hi")), "a second tap on Send")
        #expect(!model.deleteDraft())
        #expect(!model.saveDraft(body: MessageBody(plain: "Hi")))
        #expect(!model.closeUnchanged())
        #expect(model.handOff(body: MessageBody(plain: "Hi")) == nil)
        model.keepNow(body: MessageBody(plain: "Hi"))
        #expect(outcomes.log == ["send"])
        #expect(!model.isWriting)
        #expect(!model.canSend)
    }

    @Test func aDeletedMessageIsNotSent() {
        let outcomes = Outcomes()
        let model = model(outcomes)
        #expect(model.deleteDraft())
        #expect(!model.send(body: MessageBody(plain: "Hi")))
        #expect(outcomes.log == ["delete"])
    }

    @Test func aMessageHandedOffKeepsNothingMore() async {
        let outcomes = Outcomes()
        let model = model(outcomes)
        model.edited { MessageBody(plain: "Hi") }
        guard case .writing(.waiting(let wait, _, _)) = model.lifecycle else {
            Issue.record("the edit isn't waiting to be kept")
            return
        }
        let handed = model.handOff(body: MessageBody(plain: "Hi"))
        #expect(handed?.body.plain == "Hi")
        await wait.value
        model.keepNow(body: MessageBody(plain: "Hi"))
        #expect(outcomes.log.isEmpty, "the window it went to keeps it from here")
    }

    @Test func anEndedMessageTakesNoFiles() {
        let model = model(Outcomes())
        model.deleteDraft()
        #expect(!model.attach(DraftAttachment(filename: "a.pdf", mimeType: "application/pdf", data: Data([1]))))
        #expect(model.attachments.isEmpty)
    }

    /// A failed send or save brings the message back to be written; one deleted, closed or moved away stays gone.
    @Test func onlyAFailedSendOrSaveComesBack() {
        let outcomes = Outcomes()
        let sent = model(outcomes)
        sent.send(body: MessageBody(plain: "Hi"))
        sent.resumeKeeping()
        #expect(sent.isWriting)
        #expect(sent.send(body: MessageBody(plain: "Hi")), "it can go again once it is back")

        let saved = model(outcomes)
        saved.saveDraft(body: MessageBody(plain: "Hi"))
        saved.resumeKeeping()
        #expect(saved.isWriting)
        #expect(saved.saveDraft(body: MessageBody(plain: "Hi")), "it can be saved again once it is back")

        let deleted = model(outcomes)
        deleted.deleteDraft()
        let closed = model(outcomes)
        closed.closeUnchanged()
        let handedOff = model(outcomes)
        _ = handedOff.handOff(body: MessageBody(plain: "Hi"))
        for model in [deleted, closed, handedOff] {
            model.resumeKeeping()
            #expect(!model.isWriting)
        }
    }

    @Test func theComposerSendsOnceAndThenTakesNoInput() throws {
        let outcomes = Outcomes()
        var closed = 0
        let composer = ComposeViewController(viewModel: model(outcomes))
        let host = ComposeWindowController(composer: composer, placement: .sheet, closed: { closed += 1 })
        host.loadViewIfNeeded()
        composer.loadViewIfNeeded()
        composer.send()
        composer.send()
        composer.deleteDraft()
        #expect(outcomes.log == ["send"])
        #expect(closed == 1, "the host takes it off the screen once")
        #expect(!composer.view.isUserInteractionEnabled)
        let items =
            (composer.navigationItem.leftBarButtonItems ?? []) + (composer.navigationItem.rightBarButtonItems ?? [])
        #expect(!items.isEmpty && items.allSatisfy { !$0.isEnabled })
        guard case .unavailable = composer.answer(to: .send) else {
            Issue.record("Command-Return still offers to send")
            return
        }
    }

    @Test func aComposerBackAfterAFailedSendTakesInputAgain() {
        let composer = ComposeViewController(viewModel: model(Outcomes()))
        let host = ComposeWindowController(composer: composer, placement: .sheet, closed: {})
        host.loadViewIfNeeded()
        composer.loadViewIfNeeded()
        composer.send()
        composer.resumeAfterFailure()
        #expect(composer.view.isUserInteractionEnabled)
        guard case .ready = composer.answer(to: .send) else {
            Issue.record("Send isn't offered again")
            return
        }
    }
}
