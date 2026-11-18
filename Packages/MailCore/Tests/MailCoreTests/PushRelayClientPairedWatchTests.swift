import Foundation
import Testing

@testable import MailCore

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// What the iPhone tells the relay about its paired Apple Watch (ADR-023).
struct PushRelayClientPairedWatchTests {
    private let server = RecordingServer(status: 204)
    private var relay: PushRelayClient {
        PushRelayClient(baseURL: URL(string: "https://relay.example.test/")!, http: server)
    }
    private let watch = String(repeating: "c3", count: 32)
    private var paired: DeviceToken { DeviceToken(hex: "ab12", environment: .production, watch: watch.uppercased()) }

    private func body() throws -> [String: Any] {
        let request = try #require(server.requests.last)
        return try #require(try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any])
    }

    @Test func gmailRegistrationCarriesTheWatchToken() async throws {
        try await relay.register(paired, proof: "id-token")

        #expect(try body()["watchToken"] as? String == watch)
        #expect(try body()["deviceToken"] as? String == "ab12")
    }

    @Test func aRegistrationWithoutAWatchLeavesTheKeyOutSoTheRelayClearsIt() async throws {
        try await relay.register(paired.pairing(nil), proof: "id-token")

        #expect(try body()["watchToken"] == nil)
    }

    @Test func outlookAndIMAPRegistrationsCarryTheWatchToken() async throws {
        let account = AccountID.generate()
        try await relay.register(
            RelayGraphSubscription(id: "s1", clientState: "secret", account: account, device: paired, expiresAt: .now))
        #expect(try body()["watchToken"] as? String == watch)

        try await relay.register(
            RelayMailboxWatch(
                id: "w1", secret: "s", account: account, device: paired,
                server: MailServer(host: "imap.example.test", port: 993, security: .tls), username: "u",
                password: "p"))
        #expect(try body()["watchToken"] as? String == watch)
    }

    @Test func acknowledgingPostsTheAlertsID() async throws {
        try await relay.acknowledge(alert: "1b4e28ba-2fa1-11d2-883f-0016d3cca427")

        let request = try #require(server.requests.last)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/v1/acks")
        #expect(try body() as? [String: String] == ["alert": "1b4e28ba-2fa1-11d2-883f-0016d3cca427"])
    }
}
