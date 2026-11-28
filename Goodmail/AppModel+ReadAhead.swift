import MailCore

extension AppModel {
    /// Starts fetching the bodies of threads the reader is about to open, as their rows come up, show or are
    /// touched, and drops those whose rows scrolled away first.
    ///
    /// The model's errand hands each request to the fetcher in the order they came. The fetcher owns the fetches it
    /// starts and cancels them when the app leaves the foreground.
    func readAhead(_ request: ThreadFetcher.Request) {
        readAheads.yield(request)
    }
}
