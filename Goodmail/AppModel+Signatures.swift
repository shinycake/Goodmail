import MailCore
import MailStore

/// Each account's signature, for the editor in Settings.
extension AppModel {
    /// The signature stored for the account; `nil` when it has none.
    func signature(for id: AccountID) async throws -> String? {
        try await database.offMain { try $0.signature(for: id) }
    }

    /// Makes `text` the account's signature, at the service first when it keeps one. Throws if it was refused.
    /// Returns once `signatures` has it, so a composer opened next starts with it.
    func setSignature(_ text: String, for id: AccountID) async throws {
        await show(try await engine(for: id).setSignature(text))
    }
}
