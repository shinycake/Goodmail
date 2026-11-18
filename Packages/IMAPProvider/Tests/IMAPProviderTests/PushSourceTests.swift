import Foundation
import MailCore
import Synchronization
import Testing

@testable import IMAPProvider

/// How an IMAP account asks the relay to watch its Inbox.
struct PushSourceTests {
    private let source = IMAPPushSource(
        accountID: AccountID(rawValue: "account-1"), settings: .icloud(email: "me@icloud.com"),
        password: "abcd-efgh-ijkl-mnop")
    private let device = DeviceToken(hex: "ab12", environment: .sandbox)

    @Test func aNewWatchHandsTheRelayTheLogin() async throws {
        let relay = WatchRecorder()

        let (channel, _) = try await source.subscribe(device, renewing: nil, relay: relay)

        let watch = try #require(relay.registered.first)
        guard case .mailboxWatch(let id, let secret) = channel else {
            Issue.record("Expected a mailbox watch, got \(channel)")
            return
        }
        #expect(watch.id == id)
        #expect(watch.secret == secret)
        #expect(secret.count == 64)
        #expect(watch.account == AccountID(rawValue: "account-1"))
        #expect(watch.device == device)
        #expect(watch.server == MailServer(host: "imap.mail.me.com", port: 993, security: .tls))
        #expect(watch.username == "me@icloud.com")
        #expect(watch.password == "abcd-efgh-ijkl-mnop")
    }

    @Test func renewingKeepsTheWatch() async throws {
        let relay = WatchRecorder()
        let existing = PushChannel.mailboxWatch(id: "watch-1", secret: "s3cret")

        let (channel, _) = try await source.subscribe(device, renewing: existing, relay: relay)

        #expect(channel == existing)
        #expect(relay.registered.map(\.id) == ["watch-1"])
    }

    @Test func everyRefreshRegistersAgain() {
        let subscription = PushSubscription(
            device: device, channel: .mailboxWatch(id: "watch-1", secret: "s3cret"), renewedAt: .now,
            expiresAt: .now.addingTimeInterval(IMAPPushSource.watchLifetime))

        let step = PushRegistrar.step(
            level: .all, subscription: subscription, device: device, margin: source.renewalMargin, now: .now)

        #expect(step == .subscribe(renewing: subscription.channel))
    }

    @Test func unsubscribingRemovesTheWatch() async throws {
        let relay = WatchRecorder()

        try await source.unsubscribe(
            .mailboxWatch(id: "watch-1", secret: "s3cret"), deviceToken: device.hex, relay: relay)

        #expect(relay.removed == ["watch-1"])
    }
}

private final class WatchRecorder: PushRelay {
    private let watches = Mutex<[RelayMailboxWatch]>([])
    private let removals = Mutex<[String]>([])

    var registered: [RelayMailboxWatch] { watches.withLock { $0 } }
    var removed: [String] { removals.withLock { $0 } }

    var graphNotificationURL: URL { URL(string: "https://relay.example.test/v1/graph")! }
    func register(_ device: DeviceToken, proof: String) async throws {}
    func unregister(deviceToken: String, proof: String) async throws {}
    func shareMailbox(refreshToken: String, primaryOnly: Bool) async throws {}
    func shareGraphMailbox(subscriptionID: String, clientState: String, refreshToken: String) async throws {}
    func register(_ subscription: RelayGraphSubscription) async throws {}
    func unregisterGraphSubscription(id: String, clientState: String) async throws {}
    func register(_ watch: RelayMailboxWatch) async throws { watches.withLock { $0.append(watch) } }
    func unregisterMailboxWatch(id: String, secret: String) async throws { removals.withLock { $0.append(id) } }
    func acknowledge(alert id: String) async throws {}
}
