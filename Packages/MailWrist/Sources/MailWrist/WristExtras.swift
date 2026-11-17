public import MailCore

/// What only the iPhone knows about the mail, sent in its snapshot for the watch to lay over the mail it reads itself
/// (ADR-023): pins, snoozes and device-side mutes live in the iPhone's database, the Focus on the iPhone, and an
/// Outlook signature only there. With the iPhone away, the watch keeps the last extras it heard.
public struct WristExtras: Codable, Equatable, Sendable {
    public var pinned: Set<ThreadSummary.ID>
    /// Snoozed and not yet woken: hidden until the iPhone wakes them.
    public var asleep: Set<ThreadSummary.ID>
    /// Muted on the iPhone, for the services that have no mute of their own: hidden.
    public var muted: Set<ThreadSummary.ID>
    /// The accounts the Focus lets through; `nil` for every account.
    public var focus: Set<AccountID>?
    /// The signatures the service doesn't keep, which the iPhone adds to a reply.
    public var signatures: [AccountID: String]
    /// Whether the owner lets the watch read Gmail and Outlook itself.
    public var independence: WristIndependence

    public init(
        pinned: Set<ThreadSummary.ID> = [], asleep: Set<ThreadSummary.ID> = [], muted: Set<ThreadSummary.ID> = [],
        focus: Set<AccountID>? = nil, signatures: [AccountID: String] = [:],
        independence: WristIndependence = .default
    ) {
        self.pinned = pinned
        self.asleep = asleep
        self.muted = muted
        self.focus = focus
        self.signatures = signatures
        self.independence = independence
    }
}
