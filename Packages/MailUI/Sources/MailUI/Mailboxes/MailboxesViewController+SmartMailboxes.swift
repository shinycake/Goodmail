import MailCore
import UIKit

/// What a smart mailbox's row offers when held or right-clicked: Edit, Rename and Delete, then New Smart Mailbox.
extension MailboxesViewController {
    func smartMailboxMenu(for item: MailboxesViewModel.Item?) -> UIContextMenuConfiguration? {
        guard let item, let box = viewModel.smartMailbox(at: item.destination), let flow = smartMailboxFlow else {
            return nil
        }
        let viewModel = viewModel
        return UIContextMenuConfiguration(actionProvider: { [weak self] _ in
            UIMenu(children: [
                UIMenu(
                    options: .displayInline,
                    children: [
                        UIAction(title: SmartMailboxRows.edit, image: UIImage(systemName: "slider.horizontal.3")) {
                            _ in viewModel.edit(box)
                        },
                        UIAction(title: SmartMailboxRows.rename, image: UIImage(systemName: "pencil")) { _ in
                            flow.rename(box)
                        },
                        UIAction(
                            title: SmartMailboxRows.delete, image: UIImage(systemName: "trash"),
                            attributes: .destructive
                        ) { _ in
                            flow.delete(box) { self?.leave(item.destination) }
                        },
                    ]),
                UIAction(title: MailCommand.newSmartMailbox.title, image: UIImage(systemName: "plus")) { _ in
                    viewModel.newSmartMailbox()
                },
            ])
        })
    }
}

/// What the Smart Mailboxes section and its rows' menu say.
enum SmartMailboxRows {
    static var edit: String {
        String(
            localized: "Edit Smart Mailbox…", table: "SmartMailboxes", bundle: .module,
            comment: "Action: opens a smart mailbox's name, symbol and conditions")
    }

    static var rename: String {
        String(
            localized: "Rename Smart Mailbox", table: "SmartMailboxes", bundle: .module,
            comment: "Action: renames a smart mailbox, and the title of the alert that names it")
    }

    static var delete: String {
        String(
            localized: "Delete Smart Mailbox", table: "SmartMailboxes", bundle: .module,
            comment: "Action: deletes a smart mailbox")
    }
}
