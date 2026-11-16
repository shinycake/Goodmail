public import Foundation

#if canImport(FoundationNetworking)
    public import FoundationNetworking  // URLSession on Linux
#endif

/// The relay's HTTP API (PushWorker/README.md).
public struct PushRelayClient: PushRelay {
    public enum Failure: Error, Equatable {
        /// The relay refused the proof, the server refused the IMAP login, or the Graph subscription or IMAP watch
        /// is registered under another secret.
        case unauthorized
        case status(Int)
    }

    private let baseURL: URL
    private let http: any HTTPClient

    public init(baseURL: URL, http: any HTTPClient = URLSession.shared) {
        self.baseURL = baseURL
        self.http = http
    }

    public var graphNotificationURL: URL { baseURL.appending(path: "v1/graph") }

    public func register(_ device: DeviceToken, proof: String) async throws {
        try await send(
            "POST", "v1/devices",
            ["idToken": proof, "deviceToken": device.hex, "environment": device.environment.rawValue])
    }

    public func unregister(deviceToken: String, proof: String) async throws {
        try await send("DELETE", "v1/devices", ["idToken": proof, "deviceToken": deviceToken])
    }

    public func shareMailbox(refreshToken: String) async throws {
        try await send("POST", "v1/gmail/grants", ["refreshToken": refreshToken])
    }

    public func register(_ subscription: RelayGraphSubscription) async throws {
        try await send("POST", "v1/graph/subscriptions", GraphRegistration(subscription))
    }

    public func unregisterGraphSubscription(id: String, clientState: String) async throws {
        try await send("DELETE", "v1/graph/subscriptions", ["subscriptionId": id, "clientState": clientState])
    }

    public func register(_ watch: RelayMailboxWatch) async throws {
        try await send("POST", "v1/imap/watches", MailboxWatchRegistration(watch))
    }

    public func unregisterMailboxWatch(id: String, secret: String) async throws {
        try await send("DELETE", "v1/imap/watches", ["watchId": id, "secret": secret])
    }

    private func send(_ method: String, _ path: String, _ body: some Encodable) async throws {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (_, response) = try await http.data(for: request)
        switch response.statusCode {
        case 200..<300: return
        case 401, 403: throw Failure.unauthorized
        default: throw Failure.status(response.statusCode)
        }
    }
}

/// `POST v1/graph/subscriptions`'s body.
private struct GraphRegistration: Encodable {
    let subscriptionId: String
    let clientState: String
    let account: String
    let deviceToken: String
    let environment: String
    /// Milliseconds since 1970.
    let expiresAt: Int64

    init(_ subscription: RelayGraphSubscription) {
        subscriptionId = subscription.id
        clientState = subscription.clientState
        account = subscription.account.rawValue
        deviceToken = subscription.device.hex
        environment = subscription.device.environment.rawValue
        expiresAt = Int64(subscription.expiresAt.timeIntervalSince1970 * 1000)
    }
}

/// `POST v1/imap/watches`'s body.
private struct MailboxWatchRegistration: Encodable {
    let watchId: String
    let secret: String
    let account: String
    let deviceToken: String
    let environment: String
    let host: String
    let port: UInt16
    let security: String
    let username: String
    let password: String

    init(_ watch: RelayMailboxWatch) {
        watchId = watch.id
        secret = watch.secret
        account = watch.account.rawValue
        deviceToken = watch.device.hex
        environment = watch.device.environment.rawValue
        host = watch.server.host
        port = watch.server.port
        security = watch.server.security.rawValue
        username = watch.username
        password = watch.password
    }
}
