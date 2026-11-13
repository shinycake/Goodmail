import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking  // URLSession on Linux
#endif

/// The network seam. Production uses `URLSession`; tests replay recorded fixtures.
public protocol HTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

extension URLSession: HTTPClient {
    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await data(for: request, delegate: nil)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }
}
