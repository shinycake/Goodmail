import MailCore

/// A folder row that is no label, only a step of nested labels' paths, as `Extra` is when Gmail has only
/// `Extra/Unsubscribed`. Renaming or deleting it renames or deletes the labels under it.
nonisolated struct LabelGroup: Equatable {
    /// The whole path, as `Projects/Clients` for the folder `Clients` in `Projects`.
    let path: String
    let accountID: AccountID
    /// How many labels are under it, which deleting it deletes.
    let labelCount: Int
}

extension MailboxesViewModel {
    /// The labels a folder row holds; `nil` for a row that is a label or a standard mailbox.
    func labelGroup(at destination: Destination) -> LabelGroup? {
        guard case .folder(let path, let account) = destination else { return nil }
        return LabelGroup(path: path, accountID: account, labelCount: labelCount(under: path, account: account))
    }

    /// Whether `destination` shows one of the labels under `group`, which deleting the group deletes. Asked before
    /// the delete, since the directory drops the labels as soon as the service has deleted them.
    func group(_ group: LabelGroup, holds destination: Destination?) -> Bool {
        guard case .mailbox(let mailbox) = destination, mailbox.accountID == group.accountID,
            let label = directory.labels.first(where: { $0.mailbox == mailbox })
        else { return false }
        return label.name.hasPrefix(group.path + "/")
    }
}
