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

    @Test func sendsAfterTheHold() async {
        let sent = Sent()
        let model = WristReplyModel(hold: {}, deliver: { sent.texts.append($0) })
        await model.send("  Sounds good. ")
        #expect(sent.texts == ["Sounds good."])
        #expect(model.state == .sent("Sounds good."))
    }

    @Test func undoDuringTheHoldSendsNothing() async {
        let sent = Sent()
        let (gate, opener) = AsyncStream.makeStream(of: Void.self)
        let model = WristReplyModel(hold: { for await _ in gate { return } }, deliver: { sent.texts.append($0) })
        async let replying: Void = model.send("On my way.")
        while model.state == .writing { await Task.yield() }

        #expect(model.undo() == "On my way.")
        opener.yield()
        await replying
        #expect(sent.texts.isEmpty)
        #expect(model.state == .writing)
    }

    @Test func leavingDuringTheHoldStillSends() async {
        let sent = Sent()
        let model = WristReplyModel(hold: { throw CancellationError() }, deliver: { sent.texts.append($0) })
        await model.send("Thanks!")
        #expect(sent.texts == ["Thanks!"])
    }

    @Test func blankTextOrASecondSendDoesNothing() async {
        let sent = Sent()
        let model = WristReplyModel(hold: {}, deliver: { sent.texts.append($0) })
        await model.send(" \n")
        #expect(model.state == .writing)
        await model.send("Yes")
        await model.send("No")
        #expect(sent.texts == ["Yes"])
    }

    @Test func undoWithNothingHeldDoesNothing() {
        let model = WristReplyModel(hold: {}, deliver: { _ in })
        #expect(model.undo() == nil)
    }
}
