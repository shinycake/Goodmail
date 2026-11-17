import Foundation
import Synchronization
import Testing

@testable import MailCore

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// What the app sends when it shares a Gmail mailbox with the relay.
struct PushRelayClientShareTests {
    @Test func sharingSendsOnlyTheRefreshToken() async throws {
        let server = RecordingServer(status: 204)
        let relay = PushRelayClient(baseURL: URL(string: "https://relay.example.test/")!, http: server)

        try await relay.shareMailbox(refreshToken: "1//app", primaryOnly: true)

        let request = try #require(server.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/v1/gmail/grants")
        let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
        #expect(body?["refreshToken"] as? String == "1//app")
        #expect(body?["primaryOnly"] as? Bool == true)
    }

    @Test func outlookSharesUnderTheSubscriptionsClientState() async throws {
        let server = RecordingServer(status: 204)
        let relay = PushRelayClient(baseURL: URL(string: "https://relay.example.test/")!, http: server)

        try await relay.shareGraphMailbox(subscriptionID: "s1", clientState: "secret", refreshToken: "M.app")

        let request = try #require(server.requests.first)
        #expect(request.url?.path == "/v1/graph/grants")
        let body = try JSONDecoder().decode([String: String].self, from: request.httpBody ?? Data())
        #expect(body == ["subscriptionId": "s1", "clientState": "secret", "refreshToken": "M.app"])
    }

    @Test func aTokenGoogleRefusesThrows() async {
        let relay = PushRelayClient(
            baseURL: URL(string: "https://relay.example.test/")!, http: RecordingServer(status: 401))
        await #expect(throws: PushRelayClient.Failure.unauthorized) {
            try await relay.shareMailbox(refreshToken: "1//revoked", primaryOnly: false)
        }
    }
}

/// Records each request and answers every one with `status`.
final class RecordingServer: HTTPClient {
    private let status: Int
    private let log = Mutex<[URLRequest]>([])

    init(status: Int) { self.status = status }

    var requests: [URLRequest] { log.withLock { $0 } }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        log.withLock { $0.append(request) }
        return (Data(), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

/// What the app sends when it asks the relay to watch an IMAP Inbox.
struct PushRelayClientWatchTests {
    @Test func registeringAWatchSendsTheServerAndLogin() async throws {
        let server = RecordingServer(status: 204)
        let relay = PushRelayClient(baseURL: URL(string: "https://relay.example.test/")!, http: server)

        try await relay.register(
            RelayMailboxWatch(
                id: "watch-1", secret: "s3cret", account: AccountID(rawValue: "account-1"),
                device: DeviceToken(hex: "AB12", environment: .production),
                server: MailServer(host: "imap.mail.me.com", port: 993, security: .tls), username: "me@icloud.com",
                password: "abcd-efgh-ijkl-mnop"))

        let request = try #require(server.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/v1/imap/watches")
        let body = try #require(
            try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any])
        #expect(body["watchId"] as? String == "watch-1")
        #expect(body["secret"] as? String == "s3cret")
        #expect(body["account"] as? String == "account-1")
        #expect(body["deviceToken"] as? String == "ab12")
        #expect(body["environment"] as? String == "production")
        #expect(body["host"] as? String == "imap.mail.me.com")
        #expect(body["port"] as? Int == 993)
        #expect(body["security"] as? String == "tls")
        #expect(body["username"] as? String == "me@icloud.com")
        #expect(body["password"] as? String == "abcd-efgh-ijkl-mnop")
    }

    @Test func aLoginTheServerRefusesThrows() async {
        let relay = PushRelayClient(
            baseURL: URL(string: "https://relay.example.test/")!, http: RecordingServer(status: 401))
        await #expect(throws: PushRelayClient.Failure.unauthorized) {
            try await relay.unregisterMailboxWatch(id: "watch-1", secret: "s3cret")
        }
    }

    @Test func removingAWatchSendsItsIDAndSecret() async throws {
        let server = RecordingServer(status: 204)
        let relay = PushRelayClient(baseURL: URL(string: "https://relay.example.test/")!, http: server)

        try await relay.unregisterMailboxWatch(id: "watch-1", secret: "s3cret")

        let request = try #require(server.requests.first)
        #expect(request.httpMethod == "DELETE")
        #expect(request.url?.path == "/v1/imap/watches")
        let body = try JSONDecoder().decode([String: String].self, from: request.httpBody ?? Data())
        #expect(body == ["watchId": "watch-1", "secret": "s3cret"])
    }
}
