#if canImport(WatchConnectivity)
    import Foundation
    import MailCore
    import OSLog

    /// The watch's side of the link to the iPhone (ADR-022).
    public enum WristLink {
        /// Runs for the app's lifetime: shows the stored mailbox, then each snapshot the iPhone sends; stores each
        /// change and sends it to the iPhone, or hands it to `runOwn`, which must not hold the loop up, when the watch runs it itself (ADR-023); asks the
        /// iPhone for each conversation opened, and shows its answer. `ready` runs each time the link can carry data, and
        /// `stored` after each save, for the watch face to read the new mailbox.
        @MainActor
        public static func run(
            inbox: WristInboxModel, threads: WristThreads, store: WristStore, channel: WristChannel,
            runOwn: @escaping @MainActor (WristCommand) -> Void = { _ in },
            ready: @escaping @MainActor () -> Void = {},
            stored: @escaping @MainActor () -> Void = {}
        ) async {
            inbox.restore(await store.load())
            await channel.activate()
            let held = HeldRequests()
            async let receiving: Void = receive(
                from: channel, inbox: inbox, threads: threads, held: held, ready: ready)
            async let requesting: Void = request(threads, from: channel, held: held)
            for await update in inbox.updates {
                do {
                    try await store.save(update.mailbox)
                    stored()
                } catch {
                    WristChannel.log.error("Couldn't keep the watch's mail: \(error, privacy: .public)")
                }
                guard let command = update.command else { continue }
                switch command.executor {
                case .phone: await channel.send(command)
                case .watch: runOwn(command)
                }
            }
            _ = await (receiving, requesting)
        }

        @MainActor
        private static func receive(
            from channel: WristChannel, inbox: WristInboxModel, threads: WristThreads, held: HeldRequests,
            ready: @MainActor () -> Void
        ) async {
            for await event in channel.events {
                switch event {
                case .ready:
                    // What was made before the session activated, or restored from the store, didn't go: the
                    // iPhone runs each command once, so sending one again does no harm.
                    for command in inbox.mailbox.pending where command.executor == .phone {
                        await channel.send(command)
                    }
                    for id in held.take() { await request(id, from: channel, threads: threads, held: held) }
                    ready()
                case .received(let data):
                    // What this app can't read was made by a newer one.
                    inbox.receive((try? WristSnapshot.read(data)) ?? .newerVersion)
                case .thread(let data):
                    if let reply = try? JSONDecoder().decode(WristThreadReply.self, from: data) {
                        threads.receive(reply)
                    }
                case .command, .threadRequest, .watchPushToken:
                    break
                }
            }
        }

        @MainActor
        private static func request(_ threads: WristThreads, from channel: WristChannel, held: HeldRequests) async {
            for await id in threads.requests { await request(id, from: channel, threads: threads, held: held) }
        }

        /// Asks the iPhone for a conversation; one asked for before the session activated waits for `ready`, while
        /// the conversation waits for its answer.
        @MainActor
        private static func request(
            _ id: ThreadSummary.ID, from channel: WristChannel, threads: WristThreads, held: HeldRequests
        ) async {
            switch await channel.request(id) {
            case .sent: break
            case .notReady: held.hold(id)
            case .unreachable: threads.phoneIsAway(id)
            }
        }
    }

    /// The conversations asked for before the session activated, to ask for again once it is ready.
    @MainActor
    private final class HeldRequests {
        private var ids: [ThreadSummary.ID] = []

        func hold(_ id: ThreadSummary.ID) {
            if !ids.contains(id) { ids.append(id) }
        }

        func take() -> [ThreadSummary.ID] {
            defer { ids = [] }
            return ids
        }
    }
#endif
