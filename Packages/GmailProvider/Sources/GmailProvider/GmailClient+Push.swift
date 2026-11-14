import Foundation
import MailCore

extension GmailClient: PushSource {
    /// Watches last seven days; renewing with two left keeps one renewal failure from losing pushes.
    public var renewalMargin: TimeInterval { 2 * 86_400 }

    /// Registers the device for the account's address, proven by the Google ID token, then starts or renews the
    /// account's watch, which every device on the account shares.
    public func subscribe(_ device: DeviceToken, renewing channel: PushChannel?, relay: any PushRelay) async throws
        -> (channel: PushChannel, expiresAt: Date)
    {
        try await relay.register(device, proof: try await session.validIDToken())
        return (.watch, try await watch())
    }

    /// Takes the device off the relay. The watch stays, since other devices on the account share it.
    public func unsubscribe(_ channel: PushChannel, deviceToken: String, relay: any PushRelay) async throws {
        try await relay.unregister(deviceToken: deviceToken, proof: try await session.validIDToken())
    }

    /// Starts or renews the account's watch on its Inbox. Returns when it lapses.
    func watch() async throws -> Date {
        let body = GmailWatchRequest(
            topicName: GmailConfiguration.pushTopic, labelIds: [SystemLabel.inbox], labelFilterBehavior: "INCLUDE")
        let response: GmailWatchResponse = try await send("users/me/watch", method: "POST", body: body)
        guard let milliseconds = Double(response.expiration) else {
            throw GmailError(status: 0, body: "Bad watch expiration")
        }
        return Date(timeIntervalSince1970: milliseconds / 1000)
    }
}

struct GmailWatchRequest: Encodable {
    let topicName: String
    let labelIds: [String]
    let labelFilterBehavior: String
}

struct GmailWatchResponse: Decodable {
    let historyId: String
    /// Milliseconds since 1970, as a string.
    let expiration: String
}
