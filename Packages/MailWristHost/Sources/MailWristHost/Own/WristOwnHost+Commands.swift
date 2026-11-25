import Foundation
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
        /// The owner turned "Mail Without iPhone" off before the command ran, or before a reply could be queued or
        /// once it couldn't go. Nothing of it is left to go from the watch, so the iPhone runs it instead. A change
        /// queued already is given back when the switch goes off (`Handback`).
        case switchedOff
    }

    /// Makes a change the reader made on the watch to an account it reads itself: archive, trash, read and their
    /// undos go to the outbox and on to the service at once when it can be reached, a reply goes out before this
    /// returns. A `WristServer` runs each command once, however often it arrives.
    public func execute(_ command: WristCommand) async throws {
        guard command.executor == .watch else { throw Refusal.iPhoneCommand }
        guard let stretch = try await serve() else { throw Refusal.switchedOff }
        switch command.kind {
        case .pin, .snooze, .unsnooze:
            throw Refusal.iPhoneCommand
        case .reply(let text):
            try await make(command, in: stretch) { Task { try await reply(command, with: text) } }
        case .archive, .moveToInbox, .trash, .untrash, .markRead:
            guard let action = command.kind.threadAction else { return }
            // Offline, the intents stay queued for the next sync or catch-up.
            try await make(command, in: stretch) {
                Task { try await perform(action, on: command.threads, for: command.id) }
            }
        }
    }

    /// Makes `command` in `stretch` through the task `change` starts, waiting for it. The command is kept in the
    /// database first, until it settles, so that the switch going off gives it back if it didn't go, even after a
    /// relaunch. The switch going off waits for the change, and it isn't cancelled: a change runs through once begun.
    /// Throws `switchedOff` when the switch went off before a reply could be queued.
    private func make(
        _ command: WristCommand, in stretch: Stretch.ID, _ change: () -> Task<ChangeOutcome, any Error>
    ) async throws {
        try database.keepWatchChange(command.id, command: JSONEncoder().encode(command))
        let changeID = UUID()
        let task = change()
        independence.track(Change(command: command.id, task: task), as: changeID, in: stretch)
        let result = await task.result
        independence.finishChange(changeID, in: stretch)
        let current = independence.stretch?.id == stretch
        switch result {
        case .success(.went):
            try database.removeWatchChange(command.id)
        case .success(.queued), .success(.uploading):
            // Kept: given back if the switch goes off before it settles.
            break
        case .success(.notSent):
            try database.removeWatchChange(command.id)
            throw current ? Refusal.replyNotSent : Refusal.switchedOff
        case .failure(let cut as CutShort):
            // Nothing was queued: the iPhone's to make once the switch is off, as when the shelf no longer had the
            // account's provider.
            try database.removeWatchChange(command.id)
            throw current ? cut.error : Refusal.switchedOff
        case .failure(let error):
            // Kept: whatever it queued before it threw is given back if the switch goes off before it settles.
            throw error
        }
    }

    /// A reply failed before it was queued.
    private struct CutShort: Error {
        let error: any Error
    }

    /// Queues `action` on `threads`, each intent marked with the change `change`, and sends it.
    private func perform(_ action: ThreadAction, on threads: [ThreadSummary.ID], for change: UUID) async throws
        -> ChangeOutcome
    {
        _ = try await commands.perform(action, on: threads, origin: change)
        var outcome = ChangeOutcome.went
        for account in Set(threads.map(\.accountID)) {
            do {
                guard let served = independence.served[account] else {
                    outcome = .queued
                    continue
                }
                try await served.outbox.flush()
            } catch {
                outcome = .queued
            }
        }
        return outcome
    }

    /// Sends `text` as a reply in each of `command`'s conversations; the reader replies to one at a time.
    private func reply(_ command: WristCommand, with text: String) async throws -> ChangeOutcome {
        var outcome = ChangeOutcome.went
        for thread in command.threads {
            switch try await reply(to: thread, with: text, for: command.id) {
            case .went, .queued: continue
            case .uploading: outcome = .uploading
            case .notSent: return .notSent
            }
        }
        return outcome
    }

    /// Sends `text` as a reply in `thread`, noting it with the change `change` before it is queued. One that couldn't
    /// go is taken back.
    private func reply(to thread: ThreadSummary.ID, with text: String, for change: UUID) async throws -> ChangeOutcome {
        let draft: Draft?
        do {
            draft = try await answers.reply(to: thread, with: text) { [database] draft in
                try database.addDraft(draft, toWatchChange: change)
            }
        } catch {
            throw CutShort(error: error)
        }
        guard let draft else { return .went }
        if let served = independence.served[thread.accountID] {
            await Self.deliver(served, account: thread.accountID, uploads: uploads)
        }
        for message in try await database.firstValue(of: database.outgoingMessages(inThread: thread))
        where message.draft.id == draft.id {
            switch message.delivery {
            case .queued, .failed:
                try database.remove(draft.id)
                return .notSent
            case .uploading:
                return .uploading
            }
        }
        return .went
    }
}
