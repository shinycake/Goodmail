public import Foundation
public import MailCore
public import MailStore
public import MailWrist

/// Serves the Apple Watch from a mail database (ADR-022, ADR-023): the Inbox as snapshots, the watch's commands run
/// through `MailCommands`, and conversations as the chat view shows them. The iPhone runs one for the watch.
public struct WristMailHost: Sendable {
    private let database: MailDatabase
    private let commands: MailCommands
    private let answers: ThreadAnswers

    public init(database: MailDatabase, commands: MailCommands, answers: ThreadAnswers) {
        self.database = database
        self.commands = commands
        self.answers = answers
    }

    /// The Inbox as the watch lists it, again after every change to it, each made at `now()`.
    public func snapshots(
        now: @escaping @Sendable () -> Date = { .now }
    ) -> AsyncMapSequence<AsyncThrowingStream<InboxGlance, any Error>, WristSnapshot> {
        database.wristSnapshots(now: now)
    }

    /// Makes the change the reader made on the watch. A reply is sent; everything else is queued for the service.
    @concurrent public func execute(_ command: WristCommand) async throws {
        switch command.kind {
        case .reply(let text):
            for thread in command.threads { try await answers.reply(to: thread, with: text) }
        case .pin(let pinned):
            _ = try await commands.pin(command.threads, pinned)
        case .snooze(let date):
            _ = try await commands.snooze(command.threads, until: date)
        case .unsnooze:
            _ = try await commands.unsnooze(command.threads)
        case .archive, .moveToInbox, .trash, .untrash, .markRead:
            if let action = command.kind.threadAction { _ = try await commands.perform(action, on: command.threads) }
        }
    }

    /// The conversation the watch asked for, as the reader's chat view shows it: the cached messages when they're
    /// current, otherwise fetched first. `.gone` when the account or the conversation is; throws when it can't be had
    /// now.
    @concurrent public func conversation(_ id: ThreadSummary.ID) async throws -> WristThreadReply {
        guard let account = try database.accounts().first(where: { $0.id == id.accountID }) else { return .gone(id) }
        let messages = try await answers.messagesToAnswer(in: id)
        guard let first = messages.first else { return .gone(id) }
        let transcript = ChatTranscript(messages: messages, accountEmail: account.email, aliases: account.aliases)
        return .thread(WristThread(id: id, subject: first.subject, transcript: transcript))
    }
}
