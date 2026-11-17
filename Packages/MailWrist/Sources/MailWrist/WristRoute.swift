public import MailCore
public import Observation

/// Where the watch app is: the Inbox, or a conversation opened over it. A tap in the Inbox and a tap on an alert
/// mirrored from the iPhone both go through here.
@MainActor @Observable
public final class WristRoute {
    /// The conversations open over the Inbox, the last one showing.
    public var path: [ThreadSummary.ID] = []

    public init() {}

    /// Shows the conversation an alert was about, over the Inbox, in place of whatever was open.
    public func open(_ thread: ThreadSummary.ID) {
        path = [thread]
    }
}
