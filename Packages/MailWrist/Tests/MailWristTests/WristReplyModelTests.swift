import Foundation
import Testing

@testable import MailWrist

/// A reply from the watch waits a moment for Undo, then goes to the iPhone once.
@MainActor
struct WristReplyModelTests {
    /// What the model handed on to send.
    private final class Sent {
        var texts: [String] = []
    }

    /// A hold that says when it has begun and lasts until the test ends it.
    private struct Gate {
        let entered: AsyncStream<Void>
        let opener: AsyncStream<Void>.Continuation
        let hold: @Sendable () async throws -> Void

        init() {
            let (entered, enter) = AsyncStream.makeStream(of: Void.self)
            let (gate, opener) = AsyncStream.makeStream(of: Void.self)
            self.entered = entered
            self.opener = opener
            hold = {
                enter.yield()
                for await _ in gate {}
            }
        }
    }

    /// Sends `text` and waits out its hold, as the reply screen does.
    private func sendAndRelease(_ text: String, on model: WristReplyModel) async {
        model.send(text)
        if let held = model.held { await model.release(held) }
    }

    @Test func sendsAfterTheHold() async throws {
        let sent = Sent()
        let model = WristReplyModel(hold: {}, deliver: { sent.texts.append($0) })
        model.send("  Sounds good. ")
        #expect(model.held?.text == "Sounds good.")
        await model.release(try #require(model.held))
        #expect(sent.texts == ["Sounds good."])
        #expect(model.state == .sent("Sounds good."))
    }

    @Test func undoDuringTheHoldSendsNothing() async throws {
        let sent = Sent()
        let gate = Gate()
        let model = WristReplyModel(hold: gate.hold, deliver: { sent.texts.append($0) })
        model.send("On my way.")
        let held = try #require(model.held)
        async let releasing: Void = model.release(held)
        var entered = gate.entered.makeAsyncIterator()
        await entered.next()

        #expect(model.undo() == "On my way.")
        gate.opener.finish()
        await releasing
        #expect(sent.texts.isEmpty)
        #expect(model.state == .writing)
    }

    @Test func leavingDuringTheHoldStillSends() async {
        let sent = Sent()
        let model = WristReplyModel(hold: { throw CancellationError() }, deliver: { sent.texts.append($0) })
        await sendAndRelease("Thanks!", on: model)
        #expect(sent.texts == ["Thanks!"])
    }

    /// Going to the background sends the held reply at once; the hold, when it ends, sends nothing more.
    @Test func releasingNowSendsOnceWithoutTheWait() async throws {
        let sent = Sent()
        let gate = Gate()
        let model = WristReplyModel(hold: gate.hold, deliver: { sent.texts.append($0) })
        model.send("Yes")
        let held = try #require(model.held)
        async let releasing: Void = model.release(held)
        var entered = gate.entered.makeAsyncIterator()
        await entered.next()

        model.releaseNow()
        #expect(sent.texts == ["Yes"])
        #expect(model.state == .sent("Yes"))
        gate.opener.finish()
        await releasing
        #expect(sent.texts == ["Yes"])
    }

    @Test func blankTextOrASecondSendDoesNothing() async {
        let sent = Sent()
        let model = WristReplyModel(hold: {}, deliver: { sent.texts.append($0) })
        await sendAndRelease(" \n", on: model)
        #expect(model.state == .writing)
        await sendAndRelease("Yes", on: model)
        await sendAndRelease("No", on: model)
        #expect(sent.texts == ["Yes"])
    }

    /// Nothing outside the model remembers what was sent, so the same words sent again after Undo are held again,
    /// and only the new hold sends them.
    @Test func theSameWordsSentAgainAfterUndoAreHeldAgain() async throws {
        let sent = Sent()
        let gate = Gate()
        let model = WristReplyModel(hold: gate.hold, deliver: { sent.texts.append($0) })
        model.send("Yes")
        let first = try #require(model.held)
        async let releasingFirst: Void = model.release(first)
        var entered = gate.entered.makeAsyncIterator()
        await entered.next()
        #expect(model.undo() == "Yes")

        model.send("Yes")
        let second = try #require(model.held)
        #expect(second != first)
        gate.opener.finish()
        await releasingFirst
        #expect(sent.texts.isEmpty, "the hold Undo took back sends nothing")
        await model.release(second)
        #expect(sent.texts == ["Yes"])
    }

    @Test func undoWithNothingHeldDoesNothing() {
        let model = WristReplyModel(hold: {}, deliver: { _ in })
        #expect(model.undo() == nil)
    }
}
