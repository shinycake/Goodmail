import Foundation
import MailCore
import Synchronization
import Testing

@testable import OutlookProvider

#if canImport(FoundationNetworking)
    import FoundationNetworking  // URLSession on Linux
#endif

struct GraphTransportTests {
    /// Answers the token request, then Graph requests with `statuses` in turn, and 200 once they run out.
    private final class ScriptedGraph: HTTPClient {
        private let statuses: Mutex<[Int]>
        private let count = Mutex(0)

        init(_ statuses: [Int]) {
            self.statuses = Mutex(statuses)
        }

        /// How many Graph requests were sent.
        var graphRequests: Int { count.withLock { $0 } }

        func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            if request.url?.host() == "login.example.com" { return (try fixture("token"), Self.reply(request, 200)) }
            count.withLock { $0 += 1 }
            let status = statuses.withLock { $0.isEmpty ? 200 : $0.removeFirst() }
            return (status == 200 ? try fixture("empty-page") : Data(), Self.reply(request, status))
        }

        private static func reply(_ request: URLRequest, _ status: Int) -> HTTPURLResponse {
            HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        }
    }

    private func transport(_ graph: ScriptedGraph, retries: Int) throws -> GraphTransport {
        let keychain = MemorySecretStore()
        let session = OAuthSession(
            accountID: AccountID(rawValue: "o1"), client: .testing, http: graph, keychain: keychain)
        try keychain.set(Data("refresh".utf8), for: session.refreshTokenKey)
        return GraphTransport(session: session, http: graph, retryDelays: Array(repeating: .zero, count: retries))
    }

    @Test(arguments: [429, 500, 502, 503, 504])
    func throttlingAndServerErrorsAreRetried(status: Int) async throws {
        let graph = ScriptedGraph([status, status])
        let _: GraphPage<GraphFolder> = try await transport(graph, retries: 2).get("me/mailFolders")
        #expect(graph.graphRequests == 3)
    }

    @Test func aFailureThatOutlastsTheRetriesIsThrown() async throws {
        let graph = ScriptedGraph([503, 503, 503])
        await #expect(throws: GraphError(status: 503, body: "")) {
            let _: GraphPage<GraphFolder> = try await transport(graph, retries: 2).get("me/mailFolders")
        }
        #expect(graph.graphRequests == 3)
    }

    @Test(arguments: [500, 502, 503, 504])
    func aRequestThatCreatesSomethingIsNotRepeatedAfterAServerError(status: Int) async throws {
        let graph = ScriptedGraph([status])
        let url = GraphTransport.baseURL.appending(path: "me/sendMail")
        await #expect(throws: GraphError(status: status, body: "")) {
            try await transport(graph, retries: 2).send(url, method: "POST", payload: nil, replay: .onlyIfRefused)
        }
        #expect(graph.graphRequests == 1)
    }

    @Test func aRequestThatCreatesSomethingIsRepeatedWhenThrottled() async throws {
        let graph = ScriptedGraph([429])
        let url = GraphTransport.baseURL.appending(path: "me/sendMail")
        try await transport(graph, retries: 2).send(url, method: "POST", payload: nil, replay: .onlyIfRefused)
        #expect(graph.graphRequests == 2)
    }

    @Test(arguments: [400, 401, 403, 404])
    func aClientErrorIsThrownAtOnce(status: Int) async throws {
        let graph = ScriptedGraph([status])
        await #expect(throws: GraphError(status: status, body: "")) {
            let _: GraphPage<GraphFolder> = try await transport(graph, retries: 2).get("me/mailFolders")
        }
        #expect(graph.graphRequests == 1)
    }

    @Test func aMissingWellKnownFolderIsLeftOutButAnyOtherFailureFailsTheDirectory() async throws {
        // Conversation History 404s in the fixture mailbox, and only its label is missing.
        let labels = try await OutlookClient.signedIn(to: FixtureGraph(FixtureGraph.mailbox)).labels()
        #expect(labels.count == 9)

        let broken = FixtureGraph { request in
            request.graphPath == "me/mailFolders/inbox" ? "status-403" : FixtureGraph.mailbox(request)
        }
        await #expect(throws: GraphError.self) { try await OutlookClient.signedIn(to: broken).labels() }
    }

    /// Answers every Graph request after a short wait, noting the most that were ever in flight at once.
    private final class SlowGraph: HTTPClient {
        private let inFlight = Mutex((now: 0, most: 0))

        var mostInFlight: Int { inFlight.withLock { $0.most } }

        func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            let reply = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if request.url?.host() == "login.example.com" { return (try fixture("token"), reply) }
            inFlight.withLock {
                $0.now += 1
                $0.most = max($0.most, $0.now)
            }
            defer { inFlight.withLock { $0.now -= 1 } }
            try await Task.sleep(for: .milliseconds(20))
            return (try fixture("empty-page"), reply)
        }
    }

    @Test func noMoreRequestsRunAtOnceThanGraphAllowsPerMailbox() async throws {
        let graph = SlowGraph()
        let keychain = MemorySecretStore()
        let session = OAuthSession(
            accountID: AccountID(rawValue: "o1"), client: .testing, http: graph, keychain: keychain)
        try keychain.set(Data("refresh".utf8), for: session.refreshTokenKey)
        let transport = GraphTransport(session: session, http: graph, retryDelays: [])
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<20 {
                group.addTask { let _: GraphPage<GraphFolder> = try await transport.get("me/mailFolders") }
            }
            try await group.waitForAll()
        }
        #expect(graph.mostInFlight == GraphTransport.concurrentRequests)
    }

    @Test func throttlingWaitsAsLongAsGraphAsksWithinAMinute() {
        func wait(_ retryAfter: String?, planned: Duration = .seconds(1)) -> Duration {
            let response = HTTPURLResponse(
                url: GraphTransport.baseURL, statusCode: 429, httpVersion: nil,
                headerFields: retryAfter.map { ["Retry-After": $0] })!
            return GraphTransport.wait(after: response, planned: planned)
        }
        #expect(wait(nil) == .seconds(1))
        #expect(wait("7") == .seconds(7))
        #expect(wait("1", planned: .seconds(4)) == .seconds(4))
        #expect(wait("3600") == .seconds(60))
        #expect(wait("Wed, 21 Oct 2026 07:28:00 GMT") == .seconds(1))
    }

    @Test func aPageTokenThatIsntGraphsIsRefusedWithoutSendingTheToken() async throws {
        let graph = FixtureGraph(FixtureGraph.mailbox)
        let outlook = try await OutlookClient.signedIn(to: graph)
        await #expect(throws: ProviderError.rejected) {
            try await outlook.threads(matching: ThreadQuery(), pageToken: "https://evil.example.com/v1.0/me/messages")
        }
        #expect(!graph.requests.contains { $0.url?.host() == "evil.example.com" })
    }
}
