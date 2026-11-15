import MailCore
import UIKit

/// The alerts around a label change: the name to create or rename it with, or the confirmation before deleting it,
/// then the change itself, and an alert when the service refuses it. The flow owns the change it sends; leaving
/// the screen that owns the flow cancels it.
final class LabelEditFlow {
    private let editor: LabelEditor
    private weak var presenter: UIViewController?
    private var running: Task<Void, Never>?

    init(editor: LabelEditor, presenter: UIViewController) {
        self.editor = editor
        self.presenter = presenter
    }

    deinit {
        running?.cancel()
    }

    /// Asks for a name and creates the label; `created` runs once the service has it.
    func create(then created: @escaping (MailLabel) -> Void) {
        let alert = UIAlertController.labelName(
            title: String(
                localized: "New Label", table: "LabelEditing", bundle: .module,
                comment: "Action: makes a new label, and the title of the alert that names it"),
            name: nil,
            action: String(
                localized: "Create", table: "LabelEditing", bundle: .module, comment: "Button: creates the label")
        ) { [weak self, editor] name in
            self?.send(.create) { created(try await editor.create(name)) }
        }
        presenter?.present(alert, animated: true)
    }

    func rename(_ id: String, named name: String) {
        let alert = UIAlertController.labelName(
            title: String(
                localized: "Rename Label", table: "LabelEditing", bundle: .module,
                comment: "Action: renames the label, and the title of the alert that names it"),
            name: name,
            action: String(
                localized: "Rename", table: "LabelEditing", bundle: .module, comment: "Button: renames the label")
        ) { [weak self, editor] newName in
            guard newName != name else { return }
            self?.send(.rename) { try await editor.rename(id, newName) }
        }
        presenter?.present(alert, animated: true)
    }

    /// Asks first, saying how many labels are nested in it, which go with it, and what happens to their mail;
    /// `deleted` runs once the service deleted them.
    func delete(_ id: String, named name: String, nested: Int, then deleted: @escaping () -> Void) {
        let alert = UIAlertController(
            title: String(
                localized: "Delete “\(name)”?", table: "LabelEditing", bundle: .module,
                comment: "Title of the alert before deleting a label, with its name"),
            message: editor.deletion.message(nested: nested), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: Self.cancel, style: .cancel))
        alert.addAction(
            UIAlertAction(
                title: String(
                    localized: "Delete", table: "LabelEditing", bundle: .module, comment: "Button: deletes the label"),
                style: .destructive
            ) { [weak self, editor] _ in
                self?.send(.delete) {
                    try await editor.delete(id)
                    deleted()
                }
            })
        presenter?.present(alert, animated: true)
    }

    /// Runs `change`, in place of one still running, and shows why the service refused it. A cancelled change
    /// shows nothing.
    private func send(_ kind: Kind, _ change: @escaping () async throws -> Void) {
        running?.cancel()
        running = Task { [weak self] in
            do {
                try await change()
            } catch {
                guard !Task.isCancelled, let presenter = self?.presenter else { return }
                presenter.present(UIAlertController.labelEditFailed(kind, error: error), animated: true)
            }
        }
    }

    enum Kind {
        case create, rename, delete
    }

    static var cancel: String {
        String(localized: "Cancel", table: "LabelEditing", bundle: .module, comment: "Button: changes nothing")
    }
}

extension LabelDeletion {
    /// What the delete confirmation says: the labels nested in it that go too, when there are any, then what
    /// happens to the mail.
    func message(nested: Int) -> String {
        guard nested > 0 else { return consequence }
        let nestedToo = String(
            localized: "The \(nested) labels inside it are deleted too.", table: "LabelEditing", bundle: .module,
            comment: "Delete label alert: how many labels nested in it are deleted with it")
        return nestedToo + "\n" + consequence
    }

    /// What the delete confirmation says happens to the label's mail.
    var consequence: String {
        switch self {
        case .keepsMail:
            String(
                localized: "The label comes off its conversations, which stay in your mail.", table: "LabelEditing",
                bundle: .module, comment: "Delete label alert, Gmail: no mail is deleted")
        case .movesMailToTrash:
            String(
                localized: "Its mail and the labels inside it move to Deleted Items.", table: "LabelEditing",
                bundle: .module, comment: "Delete label alert, Outlook: the folder and its mail go to Deleted Items")
        case .deletesMail:
            String(
                localized: "Its mail is deleted from the server for good. You can’t undo this.",
                table: "LabelEditing", bundle: .module,
                comment: "Delete label alert, iCloud and IMAP: the folder's messages are deleted")
        }
    }
}

extension UIAlertController {
    /// Asks for a label's name, starting from `name`. The action is on only while the name names something, and
    /// hands `submit` the name without its outer spaces.
    fileprivate static func labelName(
        title: String, name: String?, action: String, submit: @escaping (String) -> Void
    ) -> UIAlertController {
        let alert = UIAlertController(title: title, message: nil, preferredStyle: .alert)
        let confirm = UIAlertAction(title: action, style: .default) { [weak alert] _ in
            guard let name = LabelName.normalized(alert?.textFields?.first?.text) else { return }
            submit(name)
        }
        confirm.isEnabled = LabelName.normalized(name) != nil
        alert.addTextField { field in
            field.text = name
            field.placeholder = String(
                localized: "Name", table: "LabelEditing", bundle: .module, comment: "Placeholder: the label's name")
            field.autocapitalizationType = .sentences
            field.clearButtonMode = .whileEditing
            field.addAction(
                UIAction { [weak field] _ in confirm.isEnabled = LabelName.normalized(field?.text) != nil },
                for: .editingChanged)
        }
        alert.addAction(UIAlertAction(title: LabelEditFlow.cancel, style: .cancel))
        alert.addAction(confirm)
        alert.preferredAction = confirm
        return alert
    }

    /// Why a label change didn't happen: a name the service refused, or anything else, such as no connection.
    fileprivate static func labelEditFailed(_ kind: LabelEditFlow.Kind, error: any Error) -> UIAlertController {
        let title =
            switch kind {
            case .create:
                String(
                    localized: "Couldn’t Create Label", table: "LabelEditing", bundle: .module,
                    comment: "Title of the alert when the service refused a new label")
            case .rename:
                String(
                    localized: "Couldn’t Rename Label", table: "LabelEditing", bundle: .module,
                    comment: "Title of the alert when the service refused a label's new name")
            case .delete:
                String(
                    localized: "Couldn’t Delete Label", table: "LabelEditing", bundle: .module,
                    comment: "Title of the alert when deleting a label failed")
            }
        let message =
            error as? ProviderError == .rejected
            ? String(
                localized: "Try another name. There may already be a label with this one.", table: "LabelEditing",
                bundle: .module, comment: "The service refused the label's name")
            : String(
                localized: "Check your connection and try again.", table: "LabelEditing", bundle: .module,
                comment: "A label change failed for another reason")
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(
            UIAlertAction(
                title: String(
                    localized: "OK", table: "LabelEditing", bundle: .module, comment: "Button: closes the alert"),
                style: .default))
        return alert
    }
}
