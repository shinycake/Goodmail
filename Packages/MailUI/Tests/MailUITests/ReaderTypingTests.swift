import Foundation
import MailCore
import Testing

@testable import MailUI

/// While the reader's reply field or find bar takes typing, its keys are the text's: Send sends the reply, and the
/// shortcuts that would throw the conversation away are dimmed, so ⌘⌫ deletes words instead.
@MainActor
struct ReaderTypingTests {
    @Test func `Send sends the reply once there is something to send`() {
        var sent = 0
        let ready = ReaderTyping.reply(sendable: true).answer(to: .send, send: { sent += 1 })
        guard case .ready(let perform, _, _) = ready else {
            Issue.record("Expected Send to be ready, got \(String(describing: ready))")
            return
        }
        perform()
        #expect(sent == 1)
        #expect(isUnavailable(ReaderTyping.reply(sendable: false).answer(to: .send, send: {})))
    }

    @Test(arguments: [ReaderTyping.conversation, .find])
    func `Send is the conversation's elsewhere`(_ typing: ReaderTyping) {
        #expect(typing.answer(to: .send, send: {}) == nil)
    }

    @Test(
        arguments: [ReaderTyping.reply(sendable: true), .reply(sendable: false), .find],
        [
            MailCommand.trash, .archive, .eraseTrash,
        ])
    func `typing dims what would take the conversation away`(_ typing: ReaderTyping, _ command: MailCommand) {
        #expect(isUnavailable(typing.answer(to: command, send: {})))
    }

    @Test(arguments: [MailCommand.trash, .archive, .eraseTrash, .reply])
    func `without typing the conversation answers`(_ command: MailCommand) {
        #expect(ReaderTyping.conversation.answer(to: command, send: {}) == nil)
    }

    private func isUnavailable(_ answer: CommandAnswer?) -> Bool {
        guard case .unavailable = answer else { return false }
        return true
    }
}
