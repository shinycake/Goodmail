import Foundation
import Synchronization
import Testing

@testable import MailCore

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// The relay calls behind the alert filter: what each sends, and how the status answer reads.
struct MailboxCheckRelayTests {
    private let relay: PushRelayClient
    private let server: RecordingRelay

    init() {
        server = RecordingRelay()
        relay = PushRelayClient(baseURL: URL(string: "https://relay.example.test/")!, http: server)
    }

    @Test func grantingSendsOnlyTheRefreshToken() async throws {
        try await relay.grantMailboxCheck(refreshToken: "1//metadata")
        let request = try #require(server.requests.first)
        #expect(request.method == "POST")
        #expect(request.path == "/v1/gmail/grants")
        #expect(request.body == ["refreshToken": "1//metadata"])
    }

    @Test func revokingAndAskingProveTheAccountWithItsIDToken() async throws {
        server.answer = #"{"active":true}"#
        #expect(try await relay.checksMailbox(proof: "id-token"))
        try await relay.revokeMailboxCheck(proof: "id-token")
        #expect(server.requests.map(\.method) == ["POST", "DELETE"])
        #expect(server.requests.map(\.path) == ["/v1/gmail/grants/status", "/v1/gmail/grants"])
        #expect(server.requests.allSatisfy { $0.body == ["idToken": "id-token"] })
    }

    @Test func aRefusedGrantThrows() async {
        server.status = 401
        await #expect(throws: PushRelayClient.Failure.unauthorized) {
            try await relay.grantMailboxCheck(refreshToken: "1//revoked")
        }
    }
}

/// Records each request and answers with `answer` and `status`.
private final class RecordingRelay: HTTPClient {
    struct Request: Sendable {
        let method: String
        let path: String
        let body: [String: String]
    }

    private let state = Mutex<(requests: [Request], answer: String, status: Int)>(([], "", 204))

    var requests: [Request] { state.withLock { $0.requests } }
    var answer: String {
        get { state.withLock { $0.answer } }
        set { state.withLock { $0.answer = newValue } }
    }
    var status: Int {
        get { state.withLock { $0.status } }
        set { state.withLock { $0.status = newValue } }
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let body = (try? JSONDecoder().decode([String: String].self, from: request.httpBody ?? Data())) ?? [:]
        let recorded = Request(method: request.httpMethod ?? "", path: request.url?.path ?? "", body: body)
        let (answer, status) = state.withLock { state in
            state.requests.append(recorded)
            return (state.answer, state.status)
        }
        return (
            Data(answer.utf8),
            HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        )
    }
}
