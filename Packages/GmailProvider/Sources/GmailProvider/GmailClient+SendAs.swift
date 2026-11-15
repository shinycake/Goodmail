import Foundation
import MailCore

/// Gmail keeps a signature on each address the account sends as; the app reads and edits the default one's, and
/// offers the verified others as aliases to send from.
extension GmailClient: SendAsSyncing {
    public func sendAs() async throws -> SendAs {
        let addresses = try await sendAsAddresses()
        guard let sender = Self.defaultSender(in: addresses) else { throw ProviderError.notFound }
        return SendAs(
            signature: HTMLEntities.plainText(fromHTML: sender.signature ?? ""),
            aliases: addresses.filter { $0.isPrimary != true && $0.verificationStatus == "accepted" }.map {
                Contact(name: $0.displayName?.isEmpty == false ? $0.displayName : nil, address: $0.sendAsEmail)
            })
    }

    /// Replaces the default address's signature, rich text and all, with `text` as HTML lines.
    public func setSignature(_ text: String) async throws {
        guard let sender = Self.defaultSender(in: try await sendAsAddresses()) else { throw ProviderError.notFound }
        let _: GmailEmpty = try await send(
            "users/me/settings/sendAs/\(sender.sendAsEmail)", method: "PATCH",
            body: ["signature": Self.signatureHTML(text)])
    }

    /// Empty for no signature, rather than one blank line.
    static func signatureHTML(_ text: String) -> String {
        text.isEmpty ? "" : HTMLText.lines(text)
    }

    private func sendAsAddresses() async throws -> [GmailSendAsList.SendAs] {
        let list: GmailSendAsList = try await send("users/me/settings/sendAs")
        return list.sendAs ?? []
    }

    /// The address new mail goes from: the one marked default, else the account's own.
    private static func defaultSender(in addresses: [GmailSendAsList.SendAs]) -> GmailSendAsList.SendAs? {
        addresses.first { $0.isDefault == true } ?? addresses.first { $0.isPrimary == true }
    }
}

/// The addresses the account sends as.
struct GmailSendAsList: Decodable {
    struct SendAs: Decodable {
        let sendAsEmail: String
        let displayName: String?
        let signature: String?
        let isPrimary: Bool?
        let isDefault: Bool?
        /// "accepted" once Gmail has verified the account may send as the address; the account's own has none.
        let verificationStatus: String?
    }

    let sendAs: [SendAs]?
}
