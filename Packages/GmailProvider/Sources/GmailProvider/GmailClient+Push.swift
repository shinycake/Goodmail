import Foundation
import MailCore

extension GmailClient: PushSource {
    /// Starts or renews the account's watch on its Inbox. One watch serves every device on the account.
    public func watch() async throws -> Date {
        let body = GmailWatchRequest(
            topicName: GmailConfiguration.pushTopic, labelIds: [SystemLabel.inbox], labelFilterBehavior: "INCLUDE")
        let response: GmailWatchResponse = try await send("users/me/watch", method: "POST", body: body)
        guard let milliseconds = Double(response.expiration) else {
            throw GmailError(status: 0, body: "Bad watch expiration")
        }
        return Date(timeIntervalSince1970: milliseconds / 1000)
    }

    /// The Google ID token, which the relay checks against the iOS client ID.
    public func relayProof() async throws -> String {
        try await session.validIDToken()
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
