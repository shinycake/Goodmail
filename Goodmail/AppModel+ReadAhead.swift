import MailCore

extension AppModel {
    /// Starts fetching the bodies of threads the reader is about to open, as their rows come up, show or are
    /// touched, and drops those whose rows scrolled away first.
    ///
    /// The task only hands the request to the fetcher, which owns the fetches it starts and cancels them when the app
    /// leaves the foreground; it has no result or failure of its own.
    func readAhead(_ request: ThreadFetcher.Request) {
        let fetcher = threadFetcher
        Task { await fetcher.handle(request) }
    }
}
