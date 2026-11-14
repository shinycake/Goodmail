import Foundation
import MailCore

#if canImport(FoundationNetworking)
    import FoundationNetworking  // URLSession on Linux
#endif

/// Outlook push: each device makes its own Graph subscription to the account's Inbox, which notifies the relay
/// when mail arrives. The subscription's `clientState` is a secret only the device, Graph and the relay know.
extension OutlookClient: PushSource {
    /// Graph keeps a mail subscription at most 4230 minutes; asking for a little less leaves room for clock skew.
    static let subscriptionLifetime: TimeInterval = 4200 * 60

    /// Subscriptions last under three days, so one is renewed each day the app runs.
    public var renewalMargin: TimeInterval { 2 * 86_400 }

    /// Renews `channel` when it is still Graph's, otherwise makes a new subscription, then tells the relay.
    public func subscribe(_ device: DeviceToken, renewing channel: PushChannel?, relay: any PushRelay) async throws
        -> (channel: PushChannel, expiresAt: Date)
    {
        let expiration = Date.now.addingTimeInterval(Self.subscriptionLifetime)
        if case .subscription(let id, let clientState) = channel {
            do {
                let renewed: GraphSubscription = try JSONDecoder.graph.decode(
                    GraphSubscription.self,
                    from: try await graph.send(
                        subscriptionURL(id), method: "PATCH", json: SubscriptionRenewal(expiration)))
                try await relay.register(relayed(id, clientState, device, renewed.expirationDateTime))
                return (.subscription(id: id, clientState: clientState), renewed.expirationDateTime)
            } catch let error as GraphError where error.status == 404 {
                // The subscription lapsed, and Graph forgot it: make another.
            }
        }
        let clientState = Self.newClientState()
        let request = SubscriptionRequest(
            notificationUrl: relay.graphNotificationURL.absoluteString, expiration: expiration,
            clientState: clientState)
        let created = try JSONDecoder.graph.decode(
            GraphSubscription.self,
            from: try await graph.send(
                GraphTransport.baseURL.appending(path: "subscriptions"), method: "POST",
                payload: (try Self.encoder.encode(request), "application/json"), replay: .onlyIfRefused))
        do {
            try await relay.register(relayed(created.id, clientState, device, created.expirationDateTime))
        } catch {
            // Best effort: a subscription the relay doesn't know only notifies it in vain until it lapses.
            try? await deleteSubscription(created.id)
            throw error
        }
        return (.subscription(id: created.id, clientState: clientState), created.expirationDateTime)
    }

    public func unsubscribe(_ channel: PushChannel, deviceToken: String, relay: any PushRelay) async throws {
        guard case .subscription(let id, let clientState) = channel else { return }
        try await relay.unregisterGraphSubscription(id: id, clientState: clientState)
        try await deleteSubscription(id)
    }

    private func deleteSubscription(_ id: String) async throws {
        do {
            try await graph.send(subscriptionURL(id), method: "DELETE", payload: nil)
        } catch let error as GraphError where error.status == 404 {
            // Already gone, as after lapsing.
        }
    }

    private func subscriptionURL(_ id: String) -> URL {
        GraphTransport.baseURL.appending(path: "subscriptions").appending(path: id)
    }

    private func relayed(_ id: String, _ clientState: String, _ device: DeviceToken, _ expiresAt: Date)
        -> RelayGraphSubscription
    {
        RelayGraphSubscription(
            id: id, clientState: clientState, account: graph.session.accountID, device: device, expiresAt: expiresAt)
    }

    /// 32 random bytes as hex.
    static func newClientState() -> String {
        var generator = SystemRandomNumberGenerator()
        return (0..<32).map { _ in String(format: "%02x", UInt8.random(in: .min ... .max, using: &generator)) }
            .joined()
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return encoder
    }()
}

/// `POST subscriptions`: new mail in the Inbox only.
struct SubscriptionRequest: Encodable {
    let changeType = "created"
    let notificationUrl: String
    let resource = "me/mailFolders('inbox')/messages"
    let expirationDateTime: String
    let clientState: String

    init(notificationUrl: String, expiration: Date, clientState: String) {
        self.notificationUrl = notificationUrl
        expirationDateTime = expiration.ISO8601Format()
        self.clientState = clientState
    }
}

struct SubscriptionRenewal: Encodable {
    let expirationDateTime: String

    init(_ expiration: Date) {
        expirationDateTime = expiration.ISO8601Format()
    }
}

struct GraphSubscription: Decodable {
    let id: String
    let expirationDateTime: Date
}
