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
        let labels = try await OutlookClient.signedIn(to: FixtureGraph(OutlookReadTests.mailbox)).labels()
        #expect(labels.count == 9)

        let broken = FixtureGraph { request in
            request.graphPath == "me/mailFolders/inbox" ? "status-403" : OutlookReadTests.mailbox(request)
        }
        await #expect(throws: GraphError.self) { try await OutlookClient.signedIn(to: broken).labels() }
    }
}
