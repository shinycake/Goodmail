import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking  // URLSession on Linux
#endif

/// The relay's HTTP API (PushWorker/README.md).
public struct PushRelayClient: PushRelay {
    public enum Failure: Error, Equatable {
        /// The relay refused the proof.
        case unauthorized
        case status(Int)
    }

    private let baseURL: URL
    private let http: any HTTPClient

    public init(baseURL: URL, http: any HTTPClient = URLSession.shared) {
        self.baseURL = baseURL
        self.http = http
    }

    public func register(_ device: DeviceToken, proof: String) async throws {
        try await send(
            "POST",
            ["idToken": proof, "deviceToken": device.hex, "environment": device.environment.rawValue])
    }

    public func unregister(deviceToken: String, proof: String) async throws {
        try await send("DELETE", ["idToken": proof, "deviceToken": deviceToken])
    }

    private func send(_ method: String, _ body: [String: String]) async throws {
        var request = URLRequest(url: baseURL.appending(path: "v1/devices"))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (_, response) = try await http.data(for: request)
        switch response.statusCode {
        case 200..<300: return
        case 401: throw Failure.unauthorized
        default: throw Failure.status(response.statusCode)
        }
    }
}
