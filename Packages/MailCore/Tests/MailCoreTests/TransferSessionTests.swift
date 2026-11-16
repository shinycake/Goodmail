#if canImport(CryptoKit)
    import Foundation
    import MailCore
    import Synchronization
    import Testing

    @Suite(.timeLimit(.minutes(1)))
    struct TransferSessionTests {
        private let gmail = Account(id: AccountID(rawValue: "g"), email: "me@gmail.com", color: .blue, service: .gmail)

        private func payload(_ chosen: Set<AccountID>) -> TransferPayload {
            TransferPayload(entries: [.init(id: gmail.id, profile: .init(gmail, position: 0), signIn: Data("t".utf8))])
        }

        private func server(
            lifetime: Duration = .seconds(30), approve: @escaping @MainActor @Sendable (String) async -> Set<AccountID>?
        )
            -> TransferServer
        {
            TransferServer(lifetime: lifetime, approve: approve, payload: { payload($0) })
        }

        @Test func theDeviceThatScannedTheCodeGetsTheChosenAccounts() async throws {
            let asked = Mutex<[String]>([])
            let server = server { device in
                asked.withLock { $0.append(device) }
                return [gmail.id]
            }
            let receiver = TransferReceiver(invitation: server.sender.invitation)
            let channel = FakeChannel(receiver.hello(device: "iPad"))

            await server.handle(channel)

            #expect(asked.withLock { $0 } == ["iPad"])
            #expect(try receiver.open(try #require(channel.sent.first)) == payload([gmail.id]))
            #expect(try await server.result() == 1)
        }

        @Test func aHelloWithoutProofGetsNoAnswerAndAsksNothing() async {
            let server = server { _ in
                Issue.record("a stranger was asked about")
                return nil
            }
            let stranger = TransferReceiver(invitation: TransferSender().invitation)
            let channel = FakeChannel(stranger.hello(device: "Not yours"))

            await server.handle(channel)

            #expect(channel.sent.isEmpty)
        }

        @Test func onlyTheFirstDeviceThatScannedTheCodeIsAsked() async throws {
            let asked = Mutex(0)
            let server = server { _ in
                asked.withLock { $0 += 1 }
                return [gmail.id]
            }
            let invitation = server.sender.invitation
            let first = FakeChannel(TransferReceiver(invitation: invitation).hello(device: "iPad"))
            let second = FakeChannel(TransferReceiver(invitation: invitation).hello(device: "Someone's iPad"))

            await server.handle(first)
            await server.handle(second)

            #expect(asked.withLock { $0 } == 1)
            #expect(first.sent.count == 1)
            #expect(second.sent.isEmpty, "a copy of the code is no use once a device claimed it")
        }

        @Test func turningTheDeviceDownTellsItAndSendsNothing() async throws {
            let server = server { _ in nil }
            let receiver = TransferReceiver(invitation: server.sender.invitation)
            let channel = FakeChannel(receiver.hello(device: "iPad"))

            await server.handle(channel)

            #expect(channel.sent == [.declined])
            #expect(try await server.result() == 0)
        }

        @Test func anUnclaimedCodeExpires() async {
            let server = server(lifetime: .milliseconds(10)) { _ in [] }

            await #expect(throws: TransferServer.Failure.expired) { try await server.result() }
        }

        @Test func aClaimedCodeWaitsForTheReaderPastItsLifetime() async throws {
            let server = server(lifetime: .milliseconds(10)) { _ in
                try? await Task.sleep(for: .milliseconds(200))
                return [gmail.id]
            }
            let channel = FakeChannel(TransferReceiver(invitation: server.sender.invitation).hello(device: "iPad"))

            async let count = server.result()
            await server.handle(channel)

            #expect(try await count == 1)
        }

        @Test func aSenderThatNeverAnswersIsNotFoundInTime() async {
            let invitation = TransferSender().invitation

            await #expect(throws: TransferClient.Failure.notFound) {
                _ = try await TransferClient.receive(
                    invitation, as: "iPad", over: SilentChannel(), findingLimit: .milliseconds(10), connected: {})
            }
        }

        @Test func theReceiverGetsWhatTheServerSends() async throws {
            let server = server { _ in [gmail.id] }
            let (serverInbox, toServer) = AsyncStream.makeStream(of: TransferMessage.self)
            let (receiverInbox, toReceiver) = AsyncStream.makeStream(of: TransferMessage.self)
            let serverSide = PipeChannel(incoming: serverInbox, outgoing: toReceiver)
            let receiverSide = PipeChannel(incoming: receiverInbox, outgoing: toServer)
            let connected = Mutex(false)

            async let handled: Void = server.handle(serverSide)
            let received = try await TransferClient.receive(
                server.sender.invitation, as: "iPad", over: receiverSide,
                connected: { connected.withLock { $0 = true } })
            await handled

            #expect(received == payload([gmail.id]))
            #expect(connected.withLock { $0 })
        }
    }

    /// A device that says one thing and records what it hears back.
    private final class FakeChannel: TransferChannel {
        private let hello: TransferMessage
        private let heard = Mutex<[TransferMessage]>([])

        init(_ hello: TransferMessage) {
            self.hello = hello
        }

        var sent: [TransferMessage] { heard.withLock { $0 } }
        func send(_ message: TransferMessage) async throws { heard.withLock { $0.append(message) } }
        func receive() async throws -> TransferMessage { hello }
    }

    /// A connection to a device that isn't there: nothing goes through, until the wait is cancelled.
    private struct SilentChannel: TransferChannel {
        func send(_ message: TransferMessage) async throws { try await Task.sleep(for: .seconds(3600)) }
        func receive() async throws -> TransferMessage {
            try await Task.sleep(for: .seconds(3600))
            throw CancellationError()
        }
    }

    /// One end of a connection between two sides in the same test.
    private struct PipeChannel: TransferChannel {
        let incoming: AsyncStream<TransferMessage>
        let outgoing: AsyncStream<TransferMessage>.Continuation

        func send(_ message: TransferMessage) async throws { outgoing.yield(message) }
        func receive() async throws -> TransferMessage {
            for await message in incoming { return message }
            throw CancellationError()
        }
    }
#endif
