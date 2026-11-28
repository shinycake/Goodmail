import MailCore
import Observation

/// The list's filter: which threads of what the store listed it shows (`ListFilter`).
extension MailboxViewModel {
    /// Shows the threads `filter` admits, or all of them when it is off, and tells the window. A filter reads the
    /// whole mailbox, so it shows every thread it admits, not only those of the window.
    func setFilter(_ new: ListFilter) {
        guard offersFilter, new != filter else { return }
        // Before the rows change, so letting go can tell what the reader reached among them.
        if new.isOn { moveWindow { $0.hold(.filter) } } else { letGo(.filter) }
        filter = new
        didChangeFilter?(new)
        regroup()
    }

    /// Whether the list shows `thread` under the filter now. A row read on this visit stays while the filter does, as
    /// in Mail, so opening a conversation under Unread doesn't take it out from under the reader, and Previous goes
    /// back to it once another opens (`FilterVisit`). A thread of an account that is gone has no facts to ask.
    func isShown(_ thread: ThreadSummary) -> Bool {
        visit.shows(thread.id) {
            guard let account = accounts[thread.id.accountID] else { return false }
            let local = MailFacts.Local(holdsAttachments: attachmentWatch.holds(thread.id))
            return filter.admits(MailFacts(thread: thread, account: account, local: local))
        }
    }

    /// Follows which threads hold files, for as long as the filter asks for them: reading every downloaded message
    /// for them costs too much to do while nothing needs it.
    func followAttachments() async {
        guard let attachmentThreads else { return }
        for await asking in Observations({ self.filter.asks(for: .withAttachments) }) {
            watchAttachments(asking, from: attachmentThreads)
        }
        watchAttachments(false, from: attachmentThreads)
    }

    /// The one place `attachmentWatch` changes: starts following when `on` and stops when not. Another choice beside
    /// With Attachments leaves the stream as it is. Stopping forgets what was heard, so turning it on again waits for
    /// the store's new answer rather than filter by an old one.
    private func watchAttachments(
        _ on: Bool, from threads: () -> AsyncThrowingStream<Set<ThreadSummary.ID>, any Error>
    ) {
        switch (on, attachmentWatch) {
        case (true, .on), (false, .off):
            return
        case (true, .off):
            let stream = threads()
            attachmentWatch = .on(Task { await follow(stream) }, held: nil)
        case (false, .on(let following, _)):
            following.cancel()
            attachmentWatch = .off
        }
    }

    private func follow(_ stream: AsyncThrowingStream<Set<ThreadSummary.ID>, any Error>) async {
        do {
            for try await threads in stream {
                // Stopped meanwhile: the stream may still hand over one last value.
                guard !Task.isCancelled, case .on(let following, _) = attachmentWatch else { return }
                attachmentWatch = .on(following, held: threads)
                regroup()
            }
        } catch {}
    }
}

/// Whether a list follows which threads hold files, which With Attachments needs, and what the store said.
nonisolated enum AttachmentWatch: Equatable, Sendable {
    case off
    /// Following, as `following` does; `held` is `nil` until the store first answers.
    case on(Task<Void, Never>, held: Set<ThreadSummary.ID>?)

    /// Whether `thread` is known to hold files, or `nil` when it isn't known to.
    func holds(_ thread: ThreadSummary.ID) -> Bool? {
        guard case .on(_, let held?) = self, held.contains(thread) else { return nil }
        return true
    }
}
