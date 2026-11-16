import Foundation

/// The relay's look at a Gmail account's history (PushWorker/README.md): with the account's metadata grant it alerts
/// only for new Inbox mail, not for every read, archive or delete.
public protocol MailboxCheckRelay: Sendable {
    /// Hands the relay a refresh token that grants only `gmail.metadata`. The relay refuses a broader one.
    func grantMailboxCheck(refreshToken: String) async throws
    /// Has the relay forget the grant of the account `proof` (a Google ID token) vouches for.
    func revokeMailboxCheck(proof: String) async throws
    /// Whether the relay holds a grant for the account `proof` vouches for.
    func checksMailbox(proof: String) async throws -> Bool
}

extension PushRelayClient: MailboxCheckRelay {
    public func grantMailboxCheck(refreshToken: String) async throws {
        try await send("POST", "v1/gmail/grants", ["refreshToken": refreshToken])
    }

    public func revokeMailboxCheck(proof: String) async throws {
        try await send("DELETE", "v1/gmail/grants", ["idToken": proof])
    }

    public func checksMailbox(proof: String) async throws -> Bool {
        let data = try await send("POST", "v1/gmail/grants/status", ["idToken": proof])
        return try JSONDecoder().decode(GrantStatus.self, from: data).active
    }
}

private struct GrantStatus: Decodable {
    let active: Bool
}
