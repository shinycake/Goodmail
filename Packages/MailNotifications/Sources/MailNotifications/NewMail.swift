import MailCore

/// A thread a push alerts for, with the one-time code its alert shows in place of the snippet.
public struct NewMail: Equatable, Sendable {
    public let thread: ThreadSummary
    /// The code from the mail's body, found because its subject or snippet names a code they don't give. `nil` for
    /// any other mail, whose alert previews the snippet.
    public let code: OneTimeCode?

    public init(thread: ThreadSummary, code: OneTimeCode? = nil) {
        self.thread = thread
        self.code = code
    }
}
