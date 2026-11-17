#if canImport(WatchConnectivity)
    public import Foundation
    import OSLog
    import WatchConnectivity

    /// What the paired device's session reports.
    public enum WristSessionEvent: Equatable, Sendable {
        /// The session can carry data now: it activated, or the watch app was installed.
        case ready
        /// The paired device sent a snapshot.
        case received(Data)
    }

    /// The link between the iPhone and the Apple Watch (ADR-022). The iPhone sends its Inbox as the application
    /// context, which the system keeps and delivers once, latest wins, even while the watch app isn't running.
    public actor WristChannel {
        static let snapshotKey = "snapshot"

        /// The session's events, for one reader for the channel's life.
        public nonisolated let events: AsyncStream<WristSessionEvent>
        private let delegate: SessionDelegate
        /// The newest snapshot the session couldn't take yet, sent once it is ready.
        private var unsent: WristSnapshot?
        private let log = Logger(subsystem: "com.idanbirman.goodmail", category: "wrist")

        public init() {
            let (events, continuation) = AsyncStream.makeStream(of: WristSessionEvent.self)
            self.events = events
            delegate = SessionDelegate(events: continuation)
        }

        public func activate() {
            guard WCSession.isSupported() else { return }
            let session = WCSession.default
            session.delegate = delegate
            session.activate()
        }

        /// The snapshots the iPhone sends, from the one it sent last, for the watch.
        public nonisolated var snapshots: some AsyncSequence<WristSnapshot.Reading, Never> {
            events.compactMap { event -> WristSnapshot.Reading? in
                guard case .received(let data) = event else { return nil }
                return try? WristSnapshot.read(data)
            }
        }

        #if os(iOS)
            /// Makes `snapshot` the watch's, now if the session can take it, otherwise once it is `ready`.
            public func send(_ snapshot: WristSnapshot) {
                unsent = snapshot
                sendUnsent()
            }

            /// Sends the snapshot that couldn't go before. Call on each `ready`.
            public func sendUnsent() {
                guard let unsent else { return }
                let session = WCSession.default
                guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else {
                    return
                }
                do {
                    try session.updateApplicationContext([Self.snapshotKey: unsent.encoded()])
                    self.unsent = nil
                } catch {
                    log.error("Couldn't send the Inbox to the watch: \(error, privacy: .public)")
                }
            }
        #endif
    }

    /// WatchConnectivity calls this on its own queue. It keeps no state: it turns each call into an event.
    private final class SessionDelegate: NSObject, WCSessionDelegate, Sendable {
        private let events: AsyncStream<WristSessionEvent>.Continuation

        init(events: AsyncStream<WristSessionEvent>.Continuation) {
            self.events = events
        }

        func session(
            _ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: (any Error)?
        ) {
            guard state == .activated else { return }
            events.yield(.ready)
            if let data = session.receivedApplicationContext[WristChannel.snapshotKey] as? Data {
                events.yield(.received(data))
            }
        }

        func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
            if let data = applicationContext[WristChannel.snapshotKey] as? Data { events.yield(.received(data)) }
        }

        #if os(iOS)
            func sessionDidBecomeInactive(_ session: WCSession) {}

            /// The reader switched to another watch: start a session with it.
            func sessionDidDeactivate(_ session: WCSession) {
                session.activate()
            }

            func sessionWatchStateDidChange(_ session: WCSession) {
                events.yield(.ready)
            }
        #endif
    }
#endif
