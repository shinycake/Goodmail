import Foundation
import MailCore
import MailUI
import Network

/// The network side of a QR code transfer. The sender advertises a Bonjour service named in its code, over Wi-Fi or
/// peer to peer; the receiver connects to it by that name. Messages go as JSON, framed by Network's `Coder`. Who
/// gets what is decided in MailCore (`TransferServer`, `TransferClient`).
nonisolated enum TransferNetwork {
    typealias Messages = Coder<TransferMessage, TransferMessage, NetworkJSONCoder>

    static var parameters: NWParametersBuilder<Messages> {
        .parameters { Coder(TransferMessage.self, using: .json) { TCP() } }.peerToPeerIncluded(true)
    }

    /// Receives the accounts from the device that showed `invitation`'s code (`TransferClient.receive`).
    @concurrent static func receive(
        _ invitation: TransferInvitation, as device: String, connected: @Sendable () async -> Void
    ) async throws -> TransferPayload {
        let endpoint = NWEndpoint.service(
            name: invitation.service, type: TransferInvitation.serviceType, domain: "local.", interface: nil)
        let channel = NetworkChannel(connection: NetworkConnection(to: endpoint, using: parameters))
        return try await TransferClient.receive(invitation, as: device, over: channel, connected: connected)
    }
}

/// A connection of the transfer protocol, as MailCore's rules speak to it.
private nonisolated struct NetworkChannel: TransferChannel {
    let connection: NetworkConnection<TransferNetwork.Messages>

    func send(_ message: TransferMessage) async throws { try await connection.send(message) }
    func receive() async throws -> TransferMessage { try await connection.receive().content }
}

/// One transfer from this device: its code, and the listener that hands each device that connects to the rules.
nonisolated struct TransferHost: TransferHosting {
    private let sender = TransferSender()
    /// The accounts to send, chosen by ID, with their sign-ins.
    private let payload: @Sendable (Set<AccountID>) async throws -> TransferPayload

    init(payload: @escaping @Sendable (Set<AccountID>) async throws -> TransferPayload) {
        self.payload = payload
    }

    var code: URL { sender.invitation.url }

    @concurrent func serve(approve: @escaping @MainActor @Sendable (String) async -> Set<AccountID>?) async throws
        -> Int
    {
        let server = TransferServer(sender: sender, approve: approve, payload: payload)
        let listener = try NetworkListener(
            for: .bonjour(name: sender.invitation.service, type: TransferInvitation.serviceType),
            using: TransferNetwork.parameters)
        return try await withThrowingTaskGroup(of: Int?.self) { group in
            group.addTask {
                try await listener.run { connection in await server.handle(NetworkChannel(connection: connection)) }
                return nil
            }
            group.addTask { try await server.result() }
            defer { group.cancelAll() }
            while let result = try await group.next() {
                if let count = result { return count }
            }
            throw CancellationError()
        }
    }
}
