#if canImport(CryptoKit)
    import Foundation
    import Synchronization

    /// One connection between the two devices of a transfer, whatever carries it: Network's in the app, a fake in
    /// tests.
    public protocol TransferChannel: Sendable {
        func send(_ message: TransferMessage) async throws
        func receive() async throws -> TransferMessage
    }

    /// The sending side's rules for who gets the accounts. Only a device that proves it scanned the code is asked
    /// about, only the first such device, and an unclaimed code expires after `lifetime`; a claimed one waits as
    /// long as the reader takes to answer.
    public final class TransferServer: Sendable {
        public enum Failure: Error, Equatable {
            /// No device proved it scanned the code while it was good.
            case expired
        }

        public let sender: TransferSender
        private let lifetime: Duration
        private let approve: @MainActor @Sendable (String) async -> Set<AccountID>?
        private let payload: @Sendable (Set<AccountID>) async throws -> TransferPayload
        private let claimed = Mutex(false)
        private let outcome: AsyncStream<Result<Int, any Error>>
        private let finished: AsyncStream<Result<Int, any Error>>.Continuation

        /// `approve` asks the reader which accounts go to the named device, `nil` for none; `payload` reads the
        /// chosen accounts with their sign-ins.
        public init(
            sender: TransferSender = TransferSender(), lifetime: Duration = .seconds(300),
            approve: @escaping @MainActor @Sendable (String) async -> Set<AccountID>?,
            payload: @escaping @Sendable (Set<AccountID>) async throws -> TransferPayload
        ) {
            self.sender = sender
            self.lifetime = lifetime
            self.approve = approve
            self.payload = payload
            (outcome, finished) = AsyncStream.makeStream()
        }

        /// Handles one device that connected. A stranger, or any device after the first, is dropped without a word.
        public func handle(_ channel: some TransferChannel) async {
            guard let hello = try? await channel.receive(), let device = try? sender.device(saying: hello),
                claim()
            else { return }
            do {
                guard let chosen = await approve(device), !chosen.isEmpty else {
                    try await channel.send(.declined)
                    finished.yield(.success(0))
                    return
                }
                let accounts = try await payload(chosen)
                try await channel.send(try sender.seal(accounts, for: hello))
                finished.yield(.success(accounts.entries.count))
            } catch {
                finished.yield(.failure(error))
            }
        }

        /// How many accounts the device that claimed the code got: 0 when the reader turned it down. Throws
        /// `Failure.expired` when no device claimed it in time.
        public func result() async throws -> Int {
            try await withThrowingTaskGroup(of: Int?.self) { group in
                group.addTask { [outcome] in
                    for await result in outcome { return try result.get() }
                    throw CancellationError()
                }
                group.addTask { [self] in
                    try await Task.sleep(for: lifetime)
                    if isClaimed { return nil }
                    throw Failure.expired
                }
                defer { group.cancelAll() }
                while let result = try await group.next() {
                    if let count = result { return count }
                }
                throw CancellationError()
            }
        }

        /// Whether this caller is the first to prove it scanned the code.
        private func claim() -> Bool {
            claimed.withLock { claimed in
                defer { claimed = true }
                return !claimed
            }
        }

        private var isClaimed: Bool { claimed.withLock { $0 } }
    }

    /// The receiving side's exchange: say hello, then read the answer.
    public enum TransferClient {
        public enum Failure: Error, Equatable {
            /// The device that showed the code didn't answer within the finding limit.
            case notFound
        }

        /// Says hello over `channel` as `device`, calls `connected` once the sender has it, and returns the accounts
        /// it sends. A sender out of reach leaves a connection waiting for good, so reaching it takes no longer than
        /// `findingLimit`. Throws `TransferReceiver.Failure.declined` when its reader says no.
        public static func receive(
            _ invitation: TransferInvitation, as device: String, over channel: some TransferChannel,
            findingLimit: Duration = .seconds(30), connected: @Sendable () async -> Void
        ) async throws -> TransferPayload {
            let receiver = TransferReceiver(invitation: invitation)
            try await withThrowingTaskGroup { group in
                group.addTask { try await channel.send(receiver.hello(device: device)) }
                group.addTask {
                    try await Task.sleep(for: findingLimit)
                    throw Failure.notFound
                }
                defer { group.cancelAll() }
                try await group.next()
            }
            await connected()
            return try receiver.open(try await channel.receive())
        }
    }
#endif
