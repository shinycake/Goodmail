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
    private let signer: (any RelaySigner)?

    /// `signer` proves each request comes from the genuine app; without one, requests go unsigned.
    public init(baseURL: URL, http: any HTTPClient = URLSession.shared, signer: (any RelaySigner)? = nil) {
        self.baseURL = baseURL
        self.http = http
        self.signer = signer
    }

    public var graphNotificationURL: URL { baseURL.appending(path: "v1/graph") }

    public func register(_ device: DeviceToken, proof: String) async throws {
        try await send(
            "POST", "v1/devices",
            DeviceRegistration(
                idToken: proof, deviceToken: device.hex, environment: device.environment.rawValue,
                watchToken: device.watch))
    }

    public func unregister(deviceToken: String, proof: String) async throws {
        try await send("DELETE", "v1/devices", ["idToken": proof, "deviceToken": deviceToken])
    }

    public func shareMailbox(refreshToken: String, primaryOnly: Bool) async throws {
        try await send("POST", "v1/gmail/grants", GmailGrant(refreshToken: refreshToken, primaryOnly: primaryOnly))
    }

    public func shareGraphMailbox(subscriptionID: String, clientState: String, refreshToken: String) async throws {
        try await send(
            "POST", "v1/graph/grants",
            ["subscriptionId": subscriptionID, "clientState": clientState, "refreshToken": refreshToken])
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

    public func acknowledge(alert id: String) async throws {
        try await send("POST", "v1/acks", ["alert": id])
    }

    private func send(_ method: String, _ path: String, _ body: some Encodable) async throws {
        let data = try JSONEncoder().encode(body)
        var status = try await send(method, path, data)
        // 428: the relay doesn't know this install's key, as after a reinstall. Attest a new one and ask once more.
        if status == 428, let signer {
            await signer.discardKey()
            status = try await send(method, path, data)
        }
        switch status {
        case 200..<300: return
        case 401, 403: throw Failure.unauthorized
        default: throw Failure.status(status)
        }
    }

    private func send(_ method: String, _ path: String, _ body: Data) async throws -> Int {
        let url = baseURL.appending(path: path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        for (field, value) in await signer?.headers(method: method, path: url.path, body: body) ?? [:] {
            request.setValue(value, forHTTPHeaderField: field)
        }
        return try await http.data(for: request).1.statusCode
    }
}

/// `POST v1/devices`'s body. A missing `watchToken` clears the one the relay stored before.
private struct DeviceRegistration: Encodable {
    let idToken: String
    let deviceToken: String
    let environment: String
    let watchToken: String?
}

/// `POST v1/graph/subscriptions`'s body.
private struct GraphRegistration: Encodable {
    let subscriptionId: String
    let clientState: String
    let account: String
    let deviceToken: String
    let environment: String
    let watchToken: String?
    /// Milliseconds since 1970.
    let expiresAt: Int64

    init(_ subscription: RelayGraphSubscription) {
        subscriptionId = subscription.id
        clientState = subscription.clientState
        account = subscription.account.rawValue
        deviceToken = subscription.device.hex
        environment = subscription.device.environment.rawValue
        watchToken = subscription.device.watch
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
    let watchToken: String?
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
        watchToken = watch.device.watch
        host = watch.server.host
        port = watch.server.port
        security = watch.server.security.rawValue
        username = watch.username
        password = watch.password
    }
}

/// The body of `POST /v1/gmail/grants`.
private struct GmailGrant: Encodable {
    let refreshToken: String
    let primaryOnly: Bool
}
