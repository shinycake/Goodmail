import Foundation
import MailCore
import Synchronization
import Testing

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// Unsubscribing does what the list asked: a one-click POST, a message from the reader's account, or a page to open.
struct ListUnsubscriberTests {
    private let bench: SendBench

    init() throws {
        bench = try SendBench()
    }

    private func unsubscriber(_ list: FakeList = FakeList(status: 200)) -> ListUnsubscriber {
        ListUnsubscriber(http: list, commands: MailCommands(store: bench.database, replay: { _ in }))
    }

    @Test func oneClickPostsTheRFC8058Form() async throws {
        let list = FakeList(status: 200)
        let url = URL(string: "https://list.example.com/u/42")!

        let outcome = try await unsubscriber(list).unsubscribe(.oneClick(url), account: bench.account)

        #expect(outcome == .done)
        let request = try #require(list.requests.first)
        #expect(request.url == url)
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
        #expect(request.httpBody == Data("List-Unsubscribe=One-Click".utf8))
    }

    @Test func aRefusedOneClickThrowsItsStatus() async throws {
        await #expect(throws: ListUnsubscriber.Failure.refused(status: 404)) {
            try await unsubscriber(FakeList(status: 404))
                .unsubscribe(.oneClick(URL(string: "https://list.example.com/u")!), account: bench.account)
        }
    }

    @Test func aMailtoListGetsAMessageFromTheReadersAccount() async throws {
        let mailto = Unsubscribe.Mailto(to: ["leave@list.example.com"])

        #expect(try await unsubscriber().unsubscribe(.mail(mailto), account: bench.account) == .done)
        let sent = try await bench.deliver(with: bench.sender())

        #expect(sent.map(\.subject) == ["unsubscribe"])
        #expect(sent.first?.to.map(\.address) == ["leave@list.example.com"])
        #expect(bench.server.sent.count == 1)
    }

    @Test func aPageIsLeftForTheReaderToOpen() async throws {
        let list = FakeList(status: 200)
        let url = URL(string: "https://list.example.com/leave")!

        #expect(try await unsubscriber(list).unsubscribe(.page(url), account: bench.account) == .openPage(url))
        #expect(list.requests.isEmpty)
    }
}

/// A list's server, answering every request with one status and keeping what it was sent.
private final class FakeList: HTTPClient {
    private let status: Int
    private let received = Mutex<[URLRequest]>([])

    init(status: Int) {
        self.status = status
    }

    var requests: [URLRequest] { received.withLock { $0 } }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        received.withLock { $0.append(request) }
        return (Data(), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}
