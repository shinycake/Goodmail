public import Foundation

/// What the watch face and the Smart Stack show of the Inbox at one moment, and how much the Smart Stack should
/// raise it then (design: "Complications and the Smart Stack").
public struct WristGlance: Equatable, Sendable {
    public enum Content: Equatable, Sendable {
        /// The iPhone hasn't sent anything yet.
        case waiting
        /// Nothing unread, as of the iPhone's last snapshot.
        case caughtUp(since: Date)
        /// `count` unread conversations; `newest` is the latest of them.
        case unread(count: Int, newest: WristRow)
        /// A one-time code under ten minutes old, shown big in place of the newest mail.
        case code(String, from: WristRow, unread: Int)
    }

    /// When the face should start showing this.
    public var date: Date
    public var content: Content
    /// How much the Smart Stack should raise the card, from 0 (not at all) to 1.
    public var relevance: Double

    /// How long a code is worth showing big after its mail arrived.
    static let codeWindow: TimeInterval = 10 * 60
    /// How long new mail counts as fresh.
    static let freshWindow: TimeInterval = 30 * 60

    /// The glance now, and the calmer ones it steps down to as a code ages out and new mail goes stale, so the face
    /// changes on time without the app running.
    public static func timeline(for snapshot: WristSnapshot?, now: Date) -> [WristGlance] {
        guard let snapshot else { return [WristGlance(date: now, content: .waiting, relevance: 0)] }
        let newest = snapshot.rows.filter(\.isUnread).max { $0.date < $1.date }
        // A code read on the iPhone has done its job.
        let coded = snapshot.rows.filter { $0.isUnread && $0.code != nil }.max { $0.date < $1.date }
        let changes = [coded.map { $0.date + codeWindow }, newest.map { $0.date + freshWindow }]
            .compactMap(\.self)
            .filter { $0 > now }
        return ([now] + Set(changes).sorted()).map { date in
            glance(at: date, snapshot: snapshot, newest: newest, coded: coded)
        }
    }

    private static func glance(at date: Date, snapshot: WristSnapshot, newest: WristRow?, coded: WristRow?)
        -> WristGlance
    {
        if let coded, let code = coded.code, date < coded.date + codeWindow {
            return WristGlance(date: date, content: .code(code, from: coded, unread: snapshot.unread), relevance: 1)
        }
        guard let newest, snapshot.unread > 0 else {
            return WristGlance(date: date, content: .caughtUp(since: snapshot.madeAt), relevance: 0)
        }
        let fresh = date < newest.date + freshWindow
        return WristGlance(
            date: date, content: .unread(count: snapshot.unread, newest: newest), relevance: fresh ? 0.6 : 0.2)
    }
}
