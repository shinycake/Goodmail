import Foundation
import MailCore
import Synchronization
import Testing

@testable import OutlookProvider

#if canImport(FoundationNetworking)
    import FoundationNetworking  // URLSession on Linux
#endif

struct OutlookPushTests {
    private let device = DeviceToken(hex: "ab12", environment: .sandbox)
    private let subscriptionID = "7f105c7d-2dc5-4530-97cd-4e7ae6534c07"
    private let expires = try! Date(
        "2026-11-16T18:23:45.9356913Z", strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true))

    /// Answers subscription requests: `renewal` for a PATCH, and the created subscription for a POST.
    private func graph(renewal: String? = "subscription") -> FixtureGraph {
        FixtureGraph { request in
            if request.url!.host() == "login.example.com" { return "token" }
            switch (request.httpMethod, request.graphPath) {
            case ("POST", "subscriptions"): return "subscription"
            case ("PATCH", _): return renewal
            case ("DELETE", _): return "empty-page"
            default: return nil
            }
        }
    }

    @Test func subscribingAsksForNewInboxMailAndRegistersItWithTheRelay() async throws {
        let graph = graph()
        let relay = RecordingRelay()
        let client = try await OutlookClient.signedIn(to: graph)

        let (channel, expiresAt) = try await client.subscribe(device, renewing: nil, relay: relay)

        let request = try #require(graph.requests.first { $0.httpMethod == "POST" && $0.graphPath == "subscriptions" })
        let body = try #require(try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: String])
        #expect(body["changeType"] == "created")
        #expect(body["resource"] == "me/mailFolders('inbox')/messages")
        #expect(body["notificationUrl"] == "https://relay.example.test/v1/graph")
        let clientState = try #require(body["clientState"])
        #expect(clientState.count == 64)
        #expect(channel == .subscription(id: subscriptionID, clientState: clientState))
        #expect(expiresAt == expires)
        #expect(
            relay.registered == [
                RelayGraphSubscription(
                    id: subscriptionID, clientState: clientState, account: AccountID(rawValue: "o1"), device: device,
                    expiresAt: expires)
            ])
    }

    @Test func renewingExtendsTheSameSubscription() async throws {
        let graph = graph()
        let client = try await OutlookClient.signedIn(to: graph)
        let channel = PushChannel.subscription(id: subscriptionID, clientState: "secret")

        let renewed = try await client.subscribe(device, renewing: channel, relay: RecordingRelay())

        #expect(renewed.channel == channel)
        #expect(
            graph.requests.contains { $0.httpMethod == "PATCH" && $0.graphPath == "subscriptions/\(subscriptionID)" })
        #expect(!graph.requests.contains { $0.httpMethod == "POST" && $0.graphPath == "subscriptions" })
    }

    @Test func aLapsedSubscriptionIsMadeAgain() async throws {
        let graph = graph(renewal: nil)
        let client = try await OutlookClient.signedIn(to: graph)

        let renewed = try await client.subscribe(
            device, renewing: .subscription(id: "gone", clientState: "secret"), relay: RecordingRelay())

        guard case .subscription(let id, let clientState) = renewed.channel else {
            Issue.record("expected a Graph subscription")
            return
        }
        #expect(id == subscriptionID)
        #expect(clientState != "secret")
    }

    @Test func unsubscribingTellsTheRelayThenDeletesTheSubscription() async throws {
        let graph = graph()
        let relay = RecordingRelay()
        let client = try await OutlookClient.signedIn(to: graph)

        try await client.unsubscribe(
            .subscription(id: subscriptionID, clientState: "secret"), deviceToken: "ab12", relay: relay)

        #expect(relay.unregistered == [subscriptionID])
        #expect(graph.requests.last?.httpMethod == "DELETE")
        #expect(graph.requests.last?.graphPath == "subscriptions/\(subscriptionID)")
    }
}

private final class RecordingRelay: PushRelay {
    private let graphs = Mutex<[RelayGraphSubscription]>([])
    private let removed = Mutex<[String]>([])

    var registered: [RelayGraphSubscription] { graphs.withLock { $0 } }
    var unregistered: [String] { removed.withLock { $0 } }

    var graphNotificationURL: URL { URL(string: "https://relay.example.test/v1/graph")! }
    func register(_ device: DeviceToken, proof: String) async throws {}
    func unregister(deviceToken: String, proof: String) async throws {}
    func register(_ subscription: RelayGraphSubscription) async throws { graphs.withLock { $0.append(subscription) } }
    func unregisterGraphSubscription(id: String, clientState: String) async throws {
        removed.withLock { $0.append(id) }
    }
}
