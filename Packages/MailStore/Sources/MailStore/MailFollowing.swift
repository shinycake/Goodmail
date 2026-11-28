import Dispatch
import GRDB

/// What follows the stored mail as it changes: the streams every screen, the badge and the alarms read. Both ways to
/// hold the database have them, the blocking `MailDatabase` for actors and extensions and the `OffMainDatabase` for
/// the main actor, since a stream reads on GRDB's queues and only delivers on the main queue (ADR-043).
public protocol MailFollowing: Sendable {
    /// The database the streams follow.
    var followed: FollowedStore { get }
}

extension OffMainDatabase: MailFollowing {
    public var followed: FollowedStore { blocking.followed }
}

extension MailDatabase: MailFollowing {}

/// Follows queries on the database, for the streams of `MailFollowing`; nothing else reads through it.
public struct FollowedStore: Sendable {
    private let reader: any DatabaseReader

    init(reader: any DatabaseReader) {
        self.reader = reader
    }

    /// Follows a query, delivering on the main queue until the stream is dropped. The query runs on GRDB's own queues,
    /// never the main thread. Emits now, then each time the result changes, from this process or another.
    func observe<Value: Equatable & Sendable>(_ fetch: @escaping @Sendable (Database) throws -> Value)
        -> AsyncThrowingStream<Value, any Error>
    {
        let observation = ValueObservation.tracking(fetch).removeDuplicates()
        return AsyncThrowingStream { continuation in
            let cancellable = observation.start(
                in: reader,
                scheduling: .async(onQueue: .main),
                onError: { continuation.finish(throwing: $0) },
                onChange: { continuation.yield($0) }
            )
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }
}
