import Foundation
import Synchronization
import Testing

@testable import MailCore

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// How the app proves to the relay that it is the genuine app.
struct RelayAttestationTests {
    private let relayURL = URL(string: "https://relay.example.test/")!
    private let at = Date(timeIntervalSince1970: 1_763_380_800)

    @Test func theFirstRequestAttestsAKeyAndSignsWithIt() async throws {
        let device = FakeDevice()
        let relay = FakeRelay()
        let store = MemorySecrets()
        let attestation = RelayAttestation(baseURL: relayURL, device: device, store: store, http: relay, now: { at })

        let headers = await attestation.headers(method: "POST", path: "/v1/devices", body: Data("{}".utf8))

        #expect(relay.paths == ["/v1/attest/challenges", "/v1/attest/keys"])
        let registration = try #require(relay.bodies.last)
        #expect(registration["keyId"] == "key-1")
        #expect(registration["challenge"] == "challenge-1")
        #expect(device.attested == [hex(RelayAttestation.sha256(Data("challenge-1".utf8)))])
        #expect(headers[RelayAttestation.keyHeader] == "key-1")
        #expect(headers[RelayAttestation.timeHeader] == "1763380800000")
        #expect(headers[RelayAttestation.assertionHeader] == Data("signed".utf8).base64EncodedString())
        #expect(try store.data(for: RelayAttestation.storageKey) == Data("key-1".utf8))
    }

    @Test func theSignatureCoversTheMethodPathTimeAndBody() async {
        let device = FakeDevice()
        let attestation = RelayAttestation(
            baseURL: relayURL, device: device, store: MemorySecrets(), http: FakeRelay(), now: { at })

        _ = await attestation.headers(method: "DELETE", path: "/v1/imap/watches", body: Data("{\"a\":1}".utf8))

        let expected = RelayAttestation.clientDataHash(
            method: "DELETE", path: "/v1/imap/watches", time: "1763380800000", body: Data("{\"a\":1}".utf8))
        #expect(device.asserted == [expected])
        #expect(expected == RelayAttestation.sha256(Data("DELETE /v1/imap/watches\n1763380800000\n{\"a\":1}".utf8)))
    }

    @Test func laterRequestsReuseTheKey() async {
        let device = FakeDevice()
        let relay = FakeRelay()
        let attestation = RelayAttestation(baseURL: relayURL, device: device, store: MemorySecrets(), http: relay)

        _ = await attestation.headers(method: "POST", path: "/v1/devices", body: Data())
        _ = await attestation.headers(method: "POST", path: "/v1/gmail/grants", body: Data())

        #expect(relay.paths.count == 2)
        #expect(device.generated == 1)
        #expect(device.asserted.count == 2)
    }

    @Test func requestsAtTheSameTimeShareOneAttestation() async {
        let device = FakeDevice()
        let relay = FakeRelay()
        let attestation = RelayAttestation(baseURL: relayURL, device: device, store: MemorySecrets(), http: relay)

        await withTaskGroup { group in
            for _ in 0..<5 {
                group.addTask { _ = await attestation.headers(method: "POST", path: "/v1/devices", body: Data()) }
            }
        }

        #expect(device.generated == 1)
        #expect(device.asserted.count == 5)
    }

    @Test func requestsAtTheSameTimeSignOneAfterAnother() async throws {
        let store = MemorySecrets()
        try store.set(Data("kept".utf8), for: RelayAttestation.storageKey)
        // On a Mac, App Attest fails every assertion of a key but the first when they overlap.
        let device = FakeDevice(failsOverlappingAssertions: true)
        let attestation = RelayAttestation(baseURL: relayURL, device: device, store: store, http: FakeRelay())

        let signed = await withTaskGroup { group in
            for _ in 0..<5 {
                group.addTask { await attestation.headers(method: "POST", path: "/v1/devices", body: Data()) }
            }
            return await group.reduce(0) { count, headers in count + (headers.isEmpty ? 0 : 1) }
        }

        #expect(signed == 5)
        #expect(device.generated == 0)
    }

    @Test func anAssertionThatFailsForAnotherReasonKeepsTheKey() async throws {
        let store = MemorySecrets()
        try store.set(Data("kept".utf8), for: RelayAttestation.storageKey)
        let device = FakeDevice(failsNextAssertion: true)
        let relay = FakeRelay()
        let attestation = RelayAttestation(baseURL: relayURL, device: device, store: store, http: relay)

        let unsigned = await attestation.headers(method: "POST", path: "/v1/devices", body: Data())
        let signed = await attestation.headers(method: "POST", path: "/v1/devices", body: Data())

        #expect(unsigned.isEmpty)
        #expect(signed[RelayAttestation.keyHeader] == "kept")
        #expect(relay.paths.isEmpty)
        #expect(try store.data(for: RelayAttestation.storageKey) == Data("kept".utf8))
    }

    @Test func aKeyFromAnEarlierLaunchIsUsedWithoutAttesting() async throws {
        let store = MemorySecrets()
        try store.set(Data("kept".utf8), for: RelayAttestation.storageKey)
        let relay = FakeRelay()
        let attestation = RelayAttestation(baseURL: relayURL, device: FakeDevice(), store: store, http: relay)

        let headers = await attestation.headers(method: "POST", path: "/v1/devices", body: Data())

        #expect(relay.paths.isEmpty)
        #expect(headers[RelayAttestation.keyHeader] == "kept")
    }

    @Test func aDiscardedKeyIsReplaced() async throws {
        let device = FakeDevice()
        let store = MemorySecrets()
        let attestation = RelayAttestation(baseURL: relayURL, device: device, store: store, http: FakeRelay())
        _ = await attestation.headers(method: "POST", path: "/v1/devices", body: Data())

        await attestation.discardKey()
        let headers = await attestation.headers(method: "POST", path: "/v1/devices", body: Data())

        #expect(headers[RelayAttestation.keyHeader] == "key-2")
        #expect(try store.data(for: RelayAttestation.storageKey) == Data("key-2".utf8))
    }

    @Test func aKeyTheEnclaveLostIsReplacedOnTheNextRequest() async throws {
        let store = MemorySecrets()
        try store.set(Data("from-before-reinstall".utf8), for: RelayAttestation.storageKey)
        let device = FakeDevice(forgets: ["from-before-reinstall"])
        let attestation = RelayAttestation(baseURL: relayURL, device: device, store: store, http: FakeRelay())

        let unsigned = await attestation.headers(method: "POST", path: "/v1/devices", body: Data())
        let signed = await attestation.headers(method: "POST", path: "/v1/devices", body: Data())

        #expect(unsigned.isEmpty)
        #expect(signed[RelayAttestation.keyHeader] == "key-1")
    }

    @Test func aRelayThatRefusesTheAttestationLeavesRequestsUnsigned() async throws {
        let store = MemorySecrets()
        let attestation = RelayAttestation(
            baseURL: relayURL, device: FakeDevice(), store: store, http: FakeRelay(keyStatus: 401))

        let headers = await attestation.headers(method: "POST", path: "/v1/devices", body: Data())

        #expect(headers.isEmpty)
        #expect(try store.data(for: RelayAttestation.storageKey) == nil)
    }

    @Test func aDeviceWithoutAppAttestSendsNothing() async {
        let relay = FakeRelay()
        let attestation = RelayAttestation(
            baseURL: relayURL, device: FakeDevice(supported: false), store: MemorySecrets(), http: relay)

        #expect(await attestation.headers(method: "POST", path: "/v1/devices", body: Data()).isEmpty)
        #expect(relay.paths.isEmpty)
    }
}

/// How the relay client carries the proof.
struct PushRelayClientSigningTests {
    @Test func everyRequestCarriesTheSignersHeadersForItsOwnBody() async throws {
        let server = StatusServer(statuses: [204])
        let signer = FakeSigner()
        let relay = PushRelayClient(baseURL: URL(string: "https://relay.example.test/")!, http: server, signer: signer)

        try await relay.unregisterMailboxWatch(id: "w", secret: "s")

        let request = try #require(server.requests.first)
        #expect(request.value(forHTTPHeaderField: "X-Signed") == "DELETE /v1/imap/watches")
        #expect(signer.signed.first?.body == request.httpBody)
    }

    @Test func aRelayThatDoesntKnowTheKeyGetsANewOneOnce() async throws {
        let server = StatusServer(statuses: [428, 204])
        let signer = FakeSigner()
        let relay = PushRelayClient(baseURL: URL(string: "https://relay.example.test/")!, http: server, signer: signer)

        try await relay.shareMailbox(refreshToken: "1//t", primaryOnly: false)

        #expect(server.requests.count == 2)
        #expect(signer.discarded == 1)
    }

    @Test func aSecondRefusalIsAnError() async {
        let server = StatusServer(statuses: [428, 428])
        let relay = PushRelayClient(
            baseURL: URL(string: "https://relay.example.test/")!, http: server, signer: FakeSigner())

        await #expect(throws: PushRelayClient.Failure.status(428)) {
            try await relay.shareMailbox(refreshToken: "1//t", primaryOnly: false)
        }
        #expect(server.requests.count == 2)
    }
}

// MARK: - Doubles

private func hex(_ data: Data) -> String {
    data.map { ($0 < 16 ? "0" : "") + String($0, radix: 16) }.joined()
}

private final class FakeDevice: AttestationDevice {
    let isSupported: Bool
    private let forgets: Set<String>
    private let failsOverlappingAssertions: Bool
    private let log = Mutex<
        (generated: Int, attested: [String], asserted: [Data], inFlight: Int, failsNextAssertion: Bool)
    >((0, [], [], 0, false))

    init(
        supported: Bool = true, forgets: Set<String> = [], failsOverlappingAssertions: Bool = false,
        failsNextAssertion: Bool = false
    ) {
        isSupported = supported
        self.forgets = forgets
        self.failsOverlappingAssertions = failsOverlappingAssertions
        log.withLock { $0.failsNextAssertion = failsNextAssertion }
    }

    var generated: Int { log.withLock { $0.generated } }
    var attested: [String] { log.withLock { $0.attested } }
    var asserted: [Data] { log.withLock { $0.asserted } }

    func generateKey() async throws -> String {
        log.withLock {
            $0.generated += 1
            return "key-\($0.generated)"
        }
    }

    func attestKey(_ keyID: String, clientDataHash: Data) async throws -> Data {
        log.withLock { $0.attested.append(hex(clientDataHash)) }
        return Data("attestation".utf8)
    }

    func generateAssertion(_ keyID: String, clientDataHash: Data) async throws -> Data {
        if forgets.contains(keyID) { throw AttestationKeyLost() }
        let (overlaps, failsNow) = log.withLock {
            $0.inFlight += 1
            defer { $0.failsNextAssertion = false }
            return ($0.inFlight > 1, $0.failsNextAssertion)
        }
        // Long enough for overlapping requests to start theirs.
        try await Task.sleep(for: .milliseconds(20))
        log.withLock { $0.inFlight -= 1 }
        if failsNow || (failsOverlappingAssertions && overlaps) { throw CocoaError(.featureUnsupported) }
        log.withLock { $0.asserted.append(clientDataHash) }
        return Data("signed".utf8)
    }
}

/// A relay that issues numbered challenges and answers key registrations with `keyStatus`.
private final class FakeRelay: HTTPClient {
    private let keyStatus: Int
    private let log = Mutex<(paths: [String], bodies: [[String: String]], challenges: Int)>(([], [], 0))

    init(keyStatus: Int = 204) { self.keyStatus = keyStatus }

    var paths: [String] { log.withLock { $0.paths } }
    var bodies: [[String: String]] { log.withLock { $0.bodies } }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let path = request.url?.path ?? ""
        let body = (try? JSONDecoder().decode([String: String].self, from: request.httpBody ?? Data())) ?? [:]
        let challenge = log.withLock {
            $0.paths.append(path)
            $0.bodies.append(body)
            $0.challenges += path.hasSuffix("challenges") ? 1 : 0
            return $0.challenges
        }
        let reply = path.hasSuffix("challenges") ? Data(#"{"challenge":"challenge-\#(challenge)"}"#.utf8) : Data()
        let status = path.hasSuffix("keys") ? keyStatus : 200
        return (reply, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

private final class FakeSigner: RelaySigner {
    private let log = Mutex<(signed: [(path: String, body: Data)], discarded: Int)>(([], 0))

    var signed: [(path: String, body: Data)] { log.withLock { $0.signed } }
    var discarded: Int { log.withLock { $0.discarded } }

    func headers(method: String, path: String, body: Data) async -> [String: String] {
        log.withLock { $0.signed.append((path, body)) }
        return ["X-Signed": "\(method) \(path)"]
    }

    func discardKey() async {
        log.withLock { $0.discarded += 1 }
    }
}

/// Answers each request with the next of `statuses`.
private final class StatusServer: HTTPClient {
    private let log: Mutex<(statuses: [Int], requests: [URLRequest])>

    init(statuses: [Int]) { log = Mutex((statuses, [])) }

    var requests: [URLRequest] { log.withLock { $0.requests } }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let status = log.withLock {
            $0.requests.append(request)
            return $0.statuses.removeFirst()
        }
        return (Data(), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

private final class MemorySecrets: SecretStore {
    private let items = Mutex<[String: Data]>([:])

    func data(for key: String) throws -> Data? { items.withLock { $0[key] } }
    func set(_ data: Data, for key: String) throws { items.withLock { $0[key] = data } }
    func remove(_ key: String) throws { items.withLock { _ = $0.removeValue(forKey: key) } }
}
