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

        try await relay.shareMailbox(refreshToken: "1//app")

        let request = try #require(server.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/v1/gmail/grants")
        let body = try JSONDecoder().decode([String: String].self, from: request.httpBody ?? Data())
        #expect(body == ["refreshToken": "1//app"])
    }

    @Test func aTokenGoogleRefusesThrows() async {
        let relay = PushRelayClient(
            baseURL: URL(string: "https://relay.example.test/")!, http: RecordingServer(status: 401))
        await #expect(throws: PushRelayClient.Failure.unauthorized) {
            try await relay.shareMailbox(refreshToken: "1//revoked")
        }
    }
}

/// Records each request and answers every one with `status`.
private final class RecordingServer: HTTPClient {
    private let status: Int
    private let log = Mutex<[URLRequest]>([])

    init(status: Int) { self.status = status }

    var requests: [URLRequest] { log.withLock { $0 } }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        log.withLock { $0.append(request) }
        return (Data(), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}
