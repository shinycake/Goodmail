/// A failure the mail service asks clients to retry after a wait.
public enum RetryableFailure: Sendable {
    /// The service turned the request away unread, because the account is over its rate limit.
    case throttled
    /// The service failed partway. It may already have done what the request asked.
    case serverError
}

/// Which failures a request may be sent again after.
public enum Replay: Sendable {
    /// Sending it twice ends as sending it once: a read, a label change, a move or a delete.
    case safe
    /// Each send makes something new, such as a sent message or a new draft. It is sent again only when the service
    /// turned it away unread, because after a server error the service may already have made it.
    case onlyIfRefused

    /// Whether a request that failed with `failure` may be sent again. `nil` is a failure that isn't retryable at
    /// all, such as a bad request.
    public func allowsRetry(after failure: RetryableFailure?) -> Bool {
        switch (failure, self) {
        case (.throttled, _), (.serverError, .safe): true
        case (.serverError, .onlyIfRefused), (nil, _): false
        }
    }
}
