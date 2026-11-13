import Foundation
import MailCore
import Synchronization

@testable import GmailProvider

#if canImport(FoundationNetworking)
    import FoundationNetworking  // URLSession on Linux
#endif

/// Replays fixture files by request path and records every request it receives.
final class FixtureHTTPClient: HTTPClient {
    struct Reply: Sendable {
        let fixture: String
        var status = 200
    }

    private let replies: Mutex<[String: [Reply]]>
    private let log = Mutex<[URLRequest]>([])

    /// `replies` maps a URL path to the replies for successive requests to it; the last one repeats.
    init(_ replies: [String: [Reply]]) {
        self.replies = Mutex(replies)
    }

    var requests: [URLRequest] { log.withLock { $0 } }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        log.withLock { $0.append(request) }
        let path = request.url!.path()
        let reply = try replies.withLock { replies in
            guard var queue = replies[path], let first = queue.first else { throw URLError(.fileDoesNotExist) }
            if queue.count > 1 { queue.removeFirst() }
            replies[path] = queue
            return first
        }
        let url = fixtureURL(reply.fixture)
        let response = HTTPURLResponse(
            url: request.url!, statusCode: reply.status, httpVersion: nil, headerFields: nil)!
        return (try Data(contentsOf: url), response)
    }
}

/// `name` may sit in a folder under Fixtures, as in `Recorded/newsletter`.
func fixtureURL(_ name: String) -> URL {
    let folder = (["Fixtures"] + name.split(separator: "/").dropLast().map(String.init)).joined(separator: "/")
    let file = String(name.split(separator: "/").last!)
    return Bundle.module.url(forResource: file, withExtension: "json", subdirectory: folder)!
}

extension URLRequest {
    var formFields: [String: String] {
        let query = String(decoding: httpBody ?? Data(), as: UTF8.self)
        let items = URLComponents(string: "?" + query)?.queryItems ?? []
        return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    }
}

final class InMemorySecretStore: SecretStore {
    private let items = Mutex<[String: Data]>([:])

    func data(for key: String) throws -> Data? { items.withLock { $0[key] } }
    func set(_ data: Data, for key: String) throws { items.withLock { $0[key] = data } }
    func remove(_ key: String) throws { _ = items.withLock { $0.removeValue(forKey: key) } }
}
