import MailCore

extension AppModel {
    /// Starts fetching the bodies of threads the reader is about to open, as their rows show or are touched.
    ///
    /// The task only hands the threads to the fetcher, which owns the fetches it starts and cancels them when the app
    /// leaves the foreground; it has no result or failure of its own.
    func readAhead(_ threads: [ThreadSummary.ID], because reason: ThreadFetcher.ReadAhead) {
        let fetcher = threadFetcher
        Task { await fetcher.readAhead(threads, because: reason) }
    }
}
