#if canImport(WatchConnectivity)
    import OSLog

    extension WristInboxModel {
        /// The watch's side of the link for the app's lifetime: shows the stored mailbox, then each snapshot the
        /// iPhone sends, and stores and sends each change.
        public func run(store: WristStore, channel: WristChannel) async {
            restore(await store.load())
            await channel.activate()
            async let following: Void = receiveSnapshots(from: channel)
            for await update in updates {
                do {
                    try await store.save(update.mailbox)
                } catch {
                    WristChannel.log.error("Couldn't keep the watch's mail: \(error, privacy: .public)")
                }
                if let command = update.command { await channel.send(command) }
            }
            await following
        }

        private func receiveSnapshots(from channel: WristChannel) async {
            for await event in channel.events {
                guard case .received(let data) = event, let reading = try? WristSnapshot.read(data) else { continue }
                receive(reading)
            }
        }
    }
#endif
