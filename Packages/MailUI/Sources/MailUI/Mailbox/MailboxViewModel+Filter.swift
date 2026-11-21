import MailCore
import Observation

/// The list's filter: which threads of what the store listed it shows (`ListFilter`).
extension MailboxViewModel {
    /// Shows the threads `filter` admits, or all of them when it is off, and tells the window.
    func setFilter(_ new: ListFilter) {
        guard offersFilter, new != filter else { return }
        filter = new
        didChangeFilter?(new)
        regroup()
    }

    /// Whether the list shows `thread` under the filter now. A thread of an account that is gone has no facts to ask.
    func isShown(_ thread: ThreadSummary) -> Bool {
        guard filter.isOn else { return true }
        guard let account = accounts[thread.id.accountID] else { return false }
        let local = MailFacts.Local(holdsAttachments: holdingAttachments.contains(thread.id) ? true : nil)
        return filter.admits(MailFacts(thread: thread, account: account, local: local))
    }

    /// Follows which threads hold files, for as long as the filter asks for them: reading every downloaded message
    /// for them costs too much to do while nothing needs it.
    func followAttachments() async {
        guard let attachmentThreads else { return }
        var following: Task<Void, Never>?
        for await asking in Observations({ self.filter.asks(for: .withAttachments) }) {
            // Another choice beside With Attachments leaves the stream as it is.
            guard asking != (following != nil) else { continue }
            following?.cancel()
            following = asking ? Task { await follow(attachmentThreads()) } : nil
        }
        following?.cancel()
    }

    private func follow(_ stream: AsyncThrowingStream<Set<ThreadSummary.ID>, any Error>) async {
        do {
            for try await threads in stream {
                if Task.isCancelled { return }
                holdingAttachments = threads
                regroup()
            }
        } catch {}
    }
}
