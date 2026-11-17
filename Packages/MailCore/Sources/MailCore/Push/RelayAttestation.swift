public import Foundation

#if canImport(CryptoKit)
    import CryptoKit
#endif
#if canImport(FoundationNetworking)
    public import FoundationNetworking  // URLSession on Linux
#endif

/// Signs the app's requests to the push relay, so the relay can tell the genuine app from a build of the public
/// source under another team (PushWorker/src/attest-routes.ts).
public protocol RelaySigner: Sendable {
    /// Headers that prove `method` `path` with `body` comes from the genuine app. Empty when this device can't prove
    /// it right now; the relay then decides whether to let the request through.
    func headers(method: String, path: String, body: Data) async -> [String: String]
    /// Forgets the key the relay no longer knows, so the next request attests a new one.
    func discardKey() async
}

/// Apple's App Attest on this device (`DCAppAttestService` in the app), behind a seam the tests replace.
public protocol AttestationDevice: Sendable {
    /// False on the Simulator and on devices without a Secure Enclave.
    var isSupported: Bool { get }
    /// A new key in the Secure Enclave, by its ID (base64 of the SHA-256 of its public key).
    func generateKey() async throws -> String
    /// Apple's attestation that the key belongs to this app on a genuine device, binding `clientDataHash`.
    func attestKey(_ keyID: String, clientDataHash: Data) async throws -> Data
    /// The key's signature over `clientDataHash`.
    func generateAssertion(_ keyID: String, clientDataHash: Data) async throws -> Data
}

/// Attests one App Attest key per install with the relay, then signs each request with it.
///
/// The key's ID is kept in the Keychain on this device only. App Attest keys don't survive a reinstall while Keychain
/// items do, so a key the device or the relay no longer knows is discarded and a new one attested.
public actor RelayAttestation: RelaySigner {
    /// Where the install's key stands.
    enum KeyState {
        /// Not read from the Keychain yet.
        case unread
        case none
        /// One request is attesting a new key; others wait for it instead of making their own.
        case attesting(Task<String, any Error>)
        case attested(String)
    }

    static let storageKey = "relay-attestation-key"
    static let keyHeader = "X-Goodmail-Attest-Key"
    static let timeHeader = "X-Goodmail-Attest-Time"
    static let assertionHeader = "X-Goodmail-Attest-Assertion"

    private let baseURL: URL
    private let device: any AttestationDevice
    private let store: any SecretStore
    private let http: any HTTPClient
    private let now: @Sendable () -> Date
    private var state = KeyState.unread

    public init(
        baseURL: URL, device: any AttestationDevice, store: any SecretStore, http: any HTTPClient = URLSession.shared,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.baseURL = baseURL
        self.device = device
        self.store = store
        self.http = http
        self.now = now
    }

    public func headers(method: String, path: String, body: Data) async -> [String: String] {
        guard device.isSupported else { return [:] }
        do {
            let keyID = try await key()
            let time = String(Int64((now().timeIntervalSince1970 * 1000).rounded(.down)))
            let assertion: Data
            do {
                assertion = try await device.generateAssertion(
                    keyID, clientDataHash: Self.clientDataHash(method: method, path: path, time: time, body: body))
            } catch {
                // The Secure Enclave lost the key, as after a reinstall: start over on the next request.
                discardKey()
                throw error
            }
            return [
                Self.keyHeader: keyID, Self.timeHeader: time, Self.assertionHeader: assertion.base64EncodedString(),
            ]
        } catch {
            // Unsigned, the relay decides; a later request attests again.
            return [:]
        }
    }

    public func discardKey() {
        if case .attesting(let task) = state { task.cancel() }
        state = .none
        try? store.remove(Self.storageKey)
    }

    /// What the device signs: `SHA-256("<method> <path>\n<time>\n" || body)`, as the relay recomputes it.
    static func clientDataHash(method: String, path: String, time: String, body: Data) -> Data {
        sha256(Data("\(method) \(path)\n\(time)\n".utf8) + body)
    }

    private func key() async throws -> String {
        if case .unread = state {
            state =
                (try? store.data(for: Self.storageKey)).flatMap { String(data: $0, encoding: .utf8) }.map(
                    KeyState.attested) ?? .none
        }
        switch state {
        case .attested(let keyID):
            return keyID
        case .attesting(let task):
            return try await task.value
        case .unread, .none:
            // Owned by `state`: every caller awaits it, and `discardKey` cancels it. Off the actor, since it's all
            // network and Secure Enclave work.
            let task = Task { @concurrent [device, http, baseURL] in
                try await Self.attest(device: device, http: http, baseURL: baseURL)
            }
            state = .attesting(task)
            let outcome = await task.result
            // Only the attempt still in `state` settles it; a discarded one changes nothing.
            guard case .attesting(let current) = state, current == task else { return try outcome.get() }
            switch outcome {
            case .success(let keyID):
                state = .attested(keyID)
                try? store.set(Data(keyID.utf8), for: Self.storageKey)
            case .failure:
                state = .none
            }
            return try outcome.get()
        }
    }

    /// Makes a key and has the relay check Apple's attestation of it against a challenge it issued.
    private static func attest(device: any AttestationDevice, http: any HTTPClient, baseURL: URL) async throws -> String
    {
        let reply = try await post(baseURL.appending(path: "v1/attest/challenges"), body: Data(), http: http)
        let challenge = try JSONDecoder().decode(Challenge.self, from: reply).challenge
        let keyID = try await device.generateKey()
        let attestation = try await device.attestKey(keyID, clientDataHash: sha256(Data(challenge.utf8)))
        let registration = KeyRegistration(
            keyId: keyID, attestation: attestation.base64EncodedString(), challenge: challenge)
        _ = try await post(
            baseURL.appending(path: "v1/attest/keys"), body: try JSONEncoder().encode(registration), http: http)
        return keyID
    }

    private static func post(_ url: URL, body: Data, http: any HTTPClient) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let (data, response) = try await http.data(for: request)
        guard (200..<300).contains(response.statusCode) else {
            throw PushRelayClient.Failure.status(response.statusCode)
        }
        return data
    }

    static func sha256(_ data: Data) -> Data {
        Data(SHA256.hash(data: data))
    }
}

private struct Challenge: Decodable {
    let challenge: String
}

private struct KeyRegistration: Encodable {
    let keyId: String
    let attestation: String
    let challenge: String
}
