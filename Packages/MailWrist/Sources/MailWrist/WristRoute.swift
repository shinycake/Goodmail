public import Foundation
public import MailCore
public import Observation

/// Where the watch app is: the Inbox, or a conversation opened over it. A tap in the Inbox, a tap on an alert
/// mirrored from the iPhone and a tap on the watch face all go through here.
@MainActor @Observable
public final class WristRoute {
    /// The conversations open over the Inbox, the last one showing.
    public var path: [ThreadSummary.ID] = []

    public init() {}

    /// Shows the conversation an alert or the watch face was about, over the Inbox, in place of whatever was open.
    public func open(_ thread: ThreadSummary.ID) {
        path = [thread]
    }

    /// Goes where a link from the watch face points: a conversation, or the Inbox. A link it doesn't know changes
    /// nothing.
    public func open(_ url: URL) {
        switch Link(url) {
        case .inbox: path = []
        case .thread(let thread): open(thread)
        case nil: break
        }
    }

    /// The link the watch face opens the app with: `thread`, or the Inbox when it's `nil`.
    public nonisolated static func url(opening thread: ThreadSummary.ID?) -> URL {
        Link(thread).url
    }
}

/// A place the watch face links to, as a URL of the app's own scheme.
private enum Link {
    case inbox
    case thread(ThreadSummary.ID)

    static let scheme = "goodmail-watch"
    static let inboxHost = "inbox"
    static let threadHost = "thread"
    static let accountKey = "account"
    static let threadKey = "thread"

    init(_ thread: ThreadSummary.ID?) {
        self = thread.map(Link.thread) ?? .inbox
    }

    init?(_ url: URL) {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false), parts.scheme == Self.scheme else {
            return nil
        }
        switch parts.host {
        case Self.inboxHost:
            self = .inbox
        case Self.threadHost:
            let items = parts.queryItems ?? []
            guard let account = items.first(where: { $0.name == Self.accountKey })?.value,
                let thread = items.first(where: { $0.name == Self.threadKey })?.value
            else { return nil }
            self = .thread(ThreadSummary.ID(accountID: AccountID(rawValue: account), threadID: thread))
        default:
            return nil
        }
    }

    var url: URL {
        var parts = URLComponents()
        parts.scheme = Self.scheme
        switch self {
        case .inbox:
            parts.host = Self.inboxHost
        case .thread(let thread):
            parts.host = Self.threadHost
            parts.queryItems = [
                URLQueryItem(name: Self.accountKey, value: thread.accountID.rawValue),
                URLQueryItem(name: Self.threadKey, value: thread.threadID),
            ]
        }
        // Built from a fixed scheme and host and percent-encoded query items, so it always forms a URL.
        return parts.url!
    }
}
