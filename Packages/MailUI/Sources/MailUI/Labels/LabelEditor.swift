import Foundation
public import MailCore

/// Changes one account's user labels at its service: Gmail's labels, Outlook's folders and IMAP's mailboxes. Each
/// change waits for the service's answer, since it can refuse a name, so none is queued for later.
public struct LabelEditor {
    /// What deleting a label does to its mail, which the confirmation spells out.
    public let deletion: LabelDeletion
    let create: (_ name: String) async throws -> MailLabel
    let rename: (_ id: String, _ name: String) async throws -> Void
    let delete: (_ id: String) async throws -> Void

    public init(
        deletion: LabelDeletion,
        create: @escaping (_ name: String) async throws -> MailLabel,
        rename: @escaping (_ id: String, _ name: String) async throws -> Void,
        delete: @escaping (_ id: String) async throws -> Void
    ) {
        self.deletion = deletion
        self.create = create
        self.rename = rename
        self.delete = delete
    }
}

/// A label's name as the reader types it.
enum LabelName {
    /// The name without the spaces around it and around each `/` of its path, or `nil` when it names nothing:
    /// blank, or with a blank step in its path, as `Projects//Goodmail`.
    static func normalized(_ text: String?) -> String? {
        let steps = (text ?? "").split(separator: "/", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        guard !steps.contains(where: \.isEmpty) else { return nil }
        return steps.joined(separator: "/")
    }
}
