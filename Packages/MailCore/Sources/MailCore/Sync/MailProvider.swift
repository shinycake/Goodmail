public import Foundation

/// What the sync engine needs from a mail service. Gmail implements it today; Graph (delta queries) and IMAP
/// (CONDSTORE) fit the same shape, because a cursor is opaque and changes are reported per thread.
public protocol MailProvider: Sendable {
    /// Every label or folder in the account, system ones included.
    func labels() async throws -> [MailLabel]

    /// A cursor for "now". Changes made after this point show up in `changes(since:)`.
    func currentCursor() async throws -> String

    /// One page of threads matching `query`, newest first, with their summaries.
    func threads(matching query: ThreadQuery, pageToken: String?) async throws -> ThreadPage

    /// The current summaries of these threads. Threads that no longer exist are listed in `missing`.
    func threads(withIDs ids: [String]) async throws -> ThreadFetch

    /// The threads that changed since `cursor`, and the cursor to continue from.
    /// Throws `ProviderError.cursorExpired` when the service no longer remembers `cursor`; resync from scratch.
    func changes(since cursor: String) async throws -> ChangeSet

    /// A thread's messages with their bodies, oldest first.
    func messages(inThread threadID: String) async throws -> [Message]

    /// The content of an attachment the provider didn't include with its message.
    func data(for attachment: Attachment, in message: Message.ID) async throws -> Data

    /// The message as the RFC 5322 bytes the service keeps, to attach it whole. Throws `ProviderError.notFound` when
    /// it is gone.
    func source(of message: Message.ID) async throws -> Data

    /// Applies `action` to every message in the thread. Throws `ProviderError.notFound` when the thread is gone.
    func perform(_ action: ThreadAction, onThread threadID: String) async throws

    /// How this provider's messages are sent: over its own connection, or as an upload that outlives the app.
    var sending: Sending { get }

    /// Saves an RFC 5322 message as a draft, in `threadID` when it answers one, in place of the saved draft
    /// `replacing`. A `replacing` draft that is gone is not an error: the message is saved as a new one. Returns the
    /// saved copy, for the next save to replace, or `nil` when the service doesn't say which it is.
    @discardableResult
    func saveDraft(_ raw: Data, inThread threadID: String?, replacing: Message.ID?) async throws -> Message.ID?

    /// Removes a saved draft. One that is already gone is not an error.
    func deleteDraft(_ message: Message.ID) async throws

    /// Everyone the account keeps contacts for, and the people it has written to.
    func contacts() async throws -> [Contact]

    /// Makes a user label (a folder, outside Gmail) named `name` and returns it. The name is a path, as
    /// `MailLabel.name` is: `Projects/Goodmail` nests in `Projects` where the service nests with `/`. Throws
    /// `ProviderError.rejected` when the service refuses the name, as for one already taken.
    func createLabel(named name: String) async throws -> MailLabel

    /// Gives the user label `id` the path `name`, with the labels nested in it. Throws `ProviderError.notFound` when
    /// it's gone and `ProviderError.rejected` when the service refuses the name.
    func renameLabel(_ id: String, to name: String) async throws

    /// Deletes the user label `id` and the labels nested in it, as `Projects/Goodmail` is in `Projects`. What
    /// happens to their mail is the service's `labelDeletion`. One that is already gone is not an error.
    func deleteLabel(_ id: String) async throws

    /// Stops using the account's sign-in, as once the account signed in afresh or is going: a token refresh under
    /// way is dropped rather than stored. A provider without a session of its own has nothing to stop.
    func endSession() async
}

extension MailProvider {
    public func endSession() async {}
}

public enum ProviderError: Error, Equatable {
    case cursorExpired
    /// The thread or message is gone.
    case notFound
    /// The provider refused the request as invalid; sending it again won't help.
    case rejected
}

public struct ThreadQuery: Codable, Equatable, Sendable {
    public var label: String?
    /// Only threads with a message on or after this date.
    public var since: Date?
    /// Only threads with a message before this date.
    public var before: Date?
    /// Only threads matching this search, in the provider's own search syntax (Gmail's `from:` and so on).
    public var text: String?

    public init(label: String? = nil, since: Date? = nil, before: Date? = nil, text: String? = nil) {
        self.label = label
        self.since = since
        self.before = before
        self.text = text
    }
}

public struct ThreadPage: Sendable {
    public var threads: [ThreadSummary]
    public var nextPageToken: String?

    public init(threads: [ThreadSummary], nextPageToken: String?) {
        self.threads = threads
        self.nextPageToken = nextPageToken
    }
}

public struct ThreadFetch: Sendable {
    public var found: [ThreadSummary]
    public var missing: [String]

    public init(found: [ThreadSummary], missing: [String]) {
        self.found = found
        self.missing = missing
    }
}

public struct ChangeSet: Equatable, Sendable {
    /// Threads with any added, deleted or relabelled message. Refetching them is always correct.
    public var threadIDs: Set<String>
    public var cursor: String

    public init(threadIDs: Set<String>, cursor: String) {
        self.threadIDs = threadIDs
        self.cursor = cursor
    }
}

public struct MailLabel: Identifiable, Equatable, Sendable {
    public enum Kind: String, Sendable {
        case system, user
    }

    /// The provider's identifier, such as Gmail's `INBOX`, `CATEGORY_SOCIAL` or `Label_12`.
    public let id: String
    public var name: String
    public var kind: Kind
    /// The label's background color as `#rrggbb`, when the user picked one.
    public var color: String?
    /// Whether the user hid the label from the label list.
    public var isHidden: Bool

    public init(id: String, name: String, kind: Kind, color: String? = nil, isHidden: Bool = false) {
        self.id = id
        self.name = name
        self.kind = kind
        self.color = color
        self.isHidden = isHidden
    }
}
