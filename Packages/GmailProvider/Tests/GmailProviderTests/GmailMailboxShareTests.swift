import Foundation
import MailCore
import Synchronization
import Testing

@testable import GmailProvider

/// The push relay's look at a Gmail mailbox: the app shares its own sign-in, so the relay can skip alerts for
/// reads, archives and deletes.
struct GmailMailboxShareTests {
    @Test func sharingHandsTheRelayTheStoredRefreshToken() async throws {
        let http = FixtureHTTPClient(["/token": [.init(fixture: "token-exchange")]])
        let session = try await OAuthSession.signIn(
            client: .gmail, code: "4/abc", pkce: .generate(), http: http, keychain: InMemorySecretStore()
        ).session
        let relay = ShareRecorder()

        try await GmailClient(session: session, http: http).shareMailbox(with: relay)

        #expect(relay.shared == ["1//fixture-refresh-token"])
    }
}

private final class ShareRecorder: PushRelay {
    private let tokens = Mutex<[String]>([])

    var shared: [String] { tokens.withLock { $0 } }

    var graphNotificationURL: URL { URL(string: "https://relay.example.test/v1/graph")! }
    func register(_ device: DeviceToken, proof: String) async throws {}
    func unregister(deviceToken: String, proof: String) async throws {}
    func shareMailbox(refreshToken: String) async throws { tokens.withLock { $0.append(refreshToken) } }
    func register(_ subscription: RelayGraphSubscription) async throws {}
    func unregisterGraphSubscription(id: String, clientState: String) async throws {}
    func register(_ watch: RelayMailboxWatch) async throws {}
    func unregisterMailboxWatch(id: String, secret: String) async throws {}
}
