import MailCore
import MailStore
public import MailWrist

extension WristOwnHost {
    /// Why the watch turned a command down.
    public enum Refusal: Error, Equatable {
        /// The command is the iPhone's to run: it was stamped for it, or it is a pin or a snooze, which only the
        /// iPhone keeps.
        case iPhoneCommand
        /// The reply couldn't be sent now. It was taken back, so it can't go later behind the reader's back.
        case replyNotSent
    }

    /// Makes a change the reader made on the watch to an account it reads itself: archive, trash, read and their
    /// undos go to the outbox and on to the service at once when it can be reached, a reply goes out before this
    /// returns. A `WristServer` runs each command once, however often it arrives.
    public func execute(_ command: WristCommand) async throws {
        guard command.executor == .watch else { throw Refusal.iPhoneCommand }
        serve()
        let accounts = Set(command.threads.map(\.accountID))
        switch command.kind {
        case .pin, .snooze, .unsnooze:
            throw Refusal.iPhoneCommand
        case .reply(let text):
            for thread in command.threads { try await reply(to: thread, with: text) }
        case .archive, .moveToInbox, .trash, .untrash, .markRead:
            guard let action = command.kind.threadAction else { return }
            _ = try await commands.perform(action, on: command.threads)
            // Offline, the intents stay queued for the next sync or catch-up.
            for account in accounts { try? await served[account]?.outbox.flush() }
        }
    }

    private func reply(to thread: ThreadSummary.ID, with text: String) async throws {
        guard let draft = try await answers.reply(to: thread, with: text) else { return }
        await deliver(thread.accountID)
        for message in try await database.firstValue(of: database.outgoingMessages(inThread: thread))
        where message.draft.id == draft.id {
            switch message.delivery {
            case .queued, .failed:
                try database.remove(draft.id)
                throw Refusal.replyNotSent
            case .uploading:
                // Whether it went is settled on the next flush, which asks the service before sending again.
                return
            }
        }
    }

    /// Sends what the account has due, and takes in how its uploads ended.
    func deliver(_ account: AccountID) async {
        guard let served = served[account] else { return }
        await served.sender.flush()
        for (id, outcome) in uploads.takeOutcomes(of: account) { _ = await served.sender.complete(id, with: outcome) }
    }

    /// Sends every queued intent and message of the accounts the watch reads, before a sync reads them back.
    func drainQueues() async {
        for (account, served) in served {
            try? await served.outbox.flush()
            await deliver(account)
        }
    }
}
