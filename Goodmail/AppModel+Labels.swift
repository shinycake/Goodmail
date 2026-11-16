import MailCore
import MailUI

extension AppModel {
    /// What creates, renames and deletes an account's user labels, and the folders that only hold them, through its sync engine so the stored labels
    /// follow the service's; `nil` for an account that isn't on the device.
    func labelEditor(for id: AccountID) -> LabelEditor? {
        guard let account = accounts.first(where: { $0.id == id }), let engine = try? engine(for: id) else {
            return nil
        }
        return LabelEditor(
            deletion: account.service.labelDeletion,
            create: { try await engine.createLabel(named: $0) },
            rename: { try await engine.renameLabel($0, to: $1) },
            delete: { try await engine.deleteLabel($0) },
            renameGroup: { try await engine.renameLabels(under: $0, to: $1) },
            deleteGroup: { try await engine.deleteLabels(under: $0) })
    }
}
