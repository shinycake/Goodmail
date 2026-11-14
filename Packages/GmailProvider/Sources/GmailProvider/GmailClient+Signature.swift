import Foundation
import MailCore

/// Gmail keeps a signature on each address the account sends as; the app reads and edits the default one's.
extension GmailClient: SignatureSyncing {
    public func signature() async throws -> String {
        HTMLEntities.plainText(fromHTML: try await defaultSender().signature ?? "")
    }

    /// Replaces the default address's signature, rich text and all, with `text` as HTML lines.
    public func setSignature(_ text: String) async throws {
        let sender = try await defaultSender()
        let _: GmailEmpty = try await send(
            "users/me/settings/sendAs/\(sender.sendAsEmail)", method: "PATCH",
            body: ["signature": Self.signatureHTML(text)])
    }

    /// Empty for no signature, rather than one blank line.
    static func signatureHTML(_ text: String) -> String {
        text.isEmpty ? "" : HTMLText.lines(text)
    }

    /// The address new mail goes from: the one marked default, else the account's own.
    private func defaultSender() async throws -> GmailSendAsList.SendAs {
        let list: GmailSendAsList = try await send("users/me/settings/sendAs")
        let addresses = list.sendAs ?? []
        guard
            let sender = addresses.first(where: { $0.isDefault == true })
                ?? addresses.first(where: { $0.isPrimary == true })
        else { throw ProviderError.notFound }
        return sender
    }
}

/// The addresses the account sends as.
struct GmailSendAsList: Decodable {
    struct SendAs: Decodable {
        let sendAsEmail: String
        let signature: String?
        let isPrimary: Bool?
        let isDefault: Bool?
    }

    let sendAs: [SendAs]?
}
