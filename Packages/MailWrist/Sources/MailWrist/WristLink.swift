#if canImport(WatchConnectivity)
    import Foundation
    import OSLog

    /// The watch's side of the link to the iPhone (ADR-022).
    public enum WristLink {
        /// Runs for the app's lifetime: shows the stored mailbox, then each snapshot the iPhone sends; stores and sends
        /// each change; asks the iPhone for each conversation opened, and shows its answer. `stored` runs after each
        /// save, for the watch face to read the new mailbox.
        @MainActor
        public static func run(
            inbox: WristInboxModel, threads: WristThreads, store: WristStore, channel: WristChannel,
            stored: @escaping @MainActor () -> Void = {}
        ) async {
            inbox.restore(await store.load())
            await channel.activate()
            async let receiving: Void = receive(from: channel, inbox: inbox, threads: threads)
            async let requesting: Void = request(threads, from: channel)
            for await update in inbox.updates {
                do {
                    try await store.save(update.mailbox)
                    stored()
                } catch {
                    WristChannel.log.error("Couldn't keep the watch's mail: \(error, privacy: .public)")
                }
                if let command = update.command { await channel.send(command) }
            }
            _ = await (receiving, requesting)
        }

        @MainActor
        private static func receive(from channel: WristChannel, inbox: WristInboxModel, threads: WristThreads) async {
            for await event in channel.events {
                switch event {
                case .received(let data):
                    if let reading = try? WristSnapshot.read(data) { inbox.receive(reading) }
                case .thread(let data):
                    if let reply = try? JSONDecoder().decode(WristThreadReply.self, from: data) {
                        threads.receive(reply)
                    }
                case .ready, .command, .threadRequest:
                    break
                }
            }
        }

        @MainActor
        private static func request(_ threads: WristThreads, from channel: WristChannel) async {
            for await id in threads.requests where await !channel.request(id) {
                threads.phoneIsAway(id)
            }
        }
    }
#endif
