import Foundation
import MailCore

/// The user's labels. Gmail nests a label by its name, as `Projects/Goodmail` sits under `Projects`, and keeps each
/// one apart: renaming `Projects` renames none of the labels under it, so the client renames them too, as Gmail's
/// own apps do.
extension GmailClient {
    public func createLabel(named name: String) async throws -> MailLabel {
        do {
            // Sent again only when refused unread: after a server error the label may exist, and a second create
            // would be refused as a duplicate.
            let label: GmailLabelList.Label = try await send(
                "users/me/labels", method: "POST", body: GmailLabelBody(name: name), replay: .onlyIfRefused)
            return label.mailLabel
        } catch let error as GmailError where error.status == 400 || error.status == 409 {
            throw ProviderError.rejected
        }
    }

    public func renameLabel(_ id: String, to name: String) async throws {
        let list: GmailLabelList = try await send("users/me/labels")
        let labels = list.labels ?? []
        guard let old = labels.first(where: { $0.id == id }) else { throw ProviderError.notFound }
        // The label first, so a name Gmail refuses leaves the ones under it as they were.
        let renames =
            [(id, name)]
            + labels.compactMap { label in
                label.name.hasPrefix(old.name + "/") ? (label.id, name + label.name.dropFirst(old.name.count)) : nil
            }
        for (id, name) in renames {
            do {
                let _: GmailLabelList.Label = try await send(
                    "users/me/labels/\(id)", method: "PATCH", body: GmailLabelBody(name: name))
            } catch let error as GmailError where error.status == 404 {
                throw ProviderError.notFound
            } catch let error as GmailError where error.status == 400 || error.status == 409 {
                throw ProviderError.rejected
            }
        }
    }

    /// Gmail takes the label off its conversations and keeps them; the labels under it stay.
    public func deleteLabel(_ id: String) async throws {
        do {
            let _: GmailEmpty = try await send("users/me/labels/\(id)", method: "DELETE")
        } catch let error as GmailError where error.status == 404 {
            return
        }
    }
}

/// A label to create, or a new name for one. Only the name changes on a rename.
struct GmailLabelBody: Encodable {
    let name: String
}
