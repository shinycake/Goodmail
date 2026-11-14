import MailCore
import MailStore

/// Each account's signature, for the editor in Settings.
extension AppModel {
    /// The signature stored for the account; `nil` when it has none.
    func signature(for id: AccountID) async throws -> String? {
        let database = database
        return try await Self.offMain { try database.signature(for: id) }
    }

    /// Makes `text` the account's signature, at the service first when it keeps one. Throws if it was refused.
    func setSignature(_ text: String, for id: AccountID) async throws {
        try await engine(for: id).setSignature(text)
    }
}
