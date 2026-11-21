import Foundation
public import MailCore
import SwiftUI
public import UIKit

/// How the screens read and store smart mailboxes and VIPs, off the main actor, and which label names the editor
/// suggests.
public struct SmartMailboxStore {
    public let box: (SmartMailbox.ID) async throws -> SmartMailbox?
    public let vips: () async throws -> VIPList
    /// Stores the box in its place, or last when it's new, with the VIPs when the VIPs box was edited.
    public let save: (SmartMailbox, _ vips: VIPList?) async throws -> Void
    public let delete: (SmartMailbox.ID) async throws -> Void
    /// The reader's labels and folders, by name, across the accounts.
    public let labelNames: () async -> [String]

    public init(
        box: @escaping (SmartMailbox.ID) async throws -> SmartMailbox?, vips: @escaping () async throws -> VIPList,
        save: @escaping (SmartMailbox, _ vips: VIPList?) async throws -> Void,
        delete: @escaping (SmartMailbox.ID) async throws -> Void, labelNames: @escaping () async -> [String]
    ) {
        self.box = box
        self.vips = vips
        self.save = save
        self.delete = delete
        self.labelNames = labelNames
    }
}

/// The sheets and alerts around a change to a smart mailbox: the editor, a new name, or the confirmation before
/// deleting it, then the change itself, and an alert when it can't be stored. Changes are stored one after another
/// in the order they were made (`TaskChain`), owned by the flow.
@MainActor
public final class SmartMailboxFlow {
    private let store: SmartMailboxStore
    /// What shows the sheets and alerts: the screen in front when each one opens.
    private let presenter: () -> UIViewController?
    private let changes = TaskChain()

    public init(store: SmartMailboxStore, presenter: @escaping () -> UIViewController?) {
        self.store = store
        self.presenter = presenter
    }

    /// Opens the editor on a new box holding what `query` finds, or on a blank one when the query can't be saved.
    public func create(from query: SearchQuery) {
        changes.run { [self] in await present(SmartMailboxDraft(query: query) ?? SmartMailboxDraft()) }
    }

    /// Opens the editor on the box, once it and the VIPs are read. A box gone meanwhile opens nothing; one whose
    /// condition the editor can't show offers to rename it instead.
    public func edit(_ id: SmartMailbox.ID) {
        changes.run { [self] in
            do {
                guard let box = try await store.box(id) else { return }
                guard let draft = SmartMailboxDraft(box, titled: box.title, vips: try await store.vips()) else {
                    return rename(box)
                }
                await present(draft)
            } catch {
                showFailure(error)
            }
        }
    }

    /// Asks for a new name, keeping everything else. Rename is on only while the name has more than spaces.
    func rename(_ box: SmartMailbox) {
        let alert = UIAlertController(
            title: String(
                localized: "Rename Smart Mailbox", table: "SmartMailboxes", bundle: .module,
                comment: "Action: renames a smart mailbox, and the title of the alert that names it"),
            message: nil, preferredStyle: .alert)
        let rename = UIAlertAction(
            title: String(
                localized: "Rename", table: "SmartMailboxes", bundle: .module,
                comment: "Button: renames the smart mailbox"),
            style: .default
        ) { [weak self, weak alert] _ in
            let name = Self.trimmed(alert?.textFields?.first?.text)
            guard !name.isEmpty, name != box.title else { return }
            var renamed = box
            renamed.name = .custom(name)
            self?.store(renamed, vips: nil)
        }
        alert.addTextField { field in
            field.text = box.title
            field.autocapitalizationType = .sentences
            field.clearButtonMode = .whileEditing
            field.addAction(
                UIAction { [weak field] _ in rename.isEnabled = !Self.trimmed(field?.text).isEmpty },
                for: .editingChanged)
        }
        alert.addAction(UIAlertAction(title: Self.cancel, style: .cancel))
        alert.addAction(rename)
        alert.preferredAction = rename
        presenter()?.present(alert, animated: true)
    }

    private static func trimmed(_ text: String?) -> String {
        (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static var cancel: String {
        String(localized: "Cancel", table: "SmartMailboxes", bundle: .module, comment: "Button: changes nothing")
    }

    /// Asks first; `deleted` runs once the box is gone.
    func delete(_ box: SmartMailbox, then deleted: @escaping () -> Void) {
        let alert = UIAlertController(
            title: String(
                localized: "Delete “\(box.title)”?", table: "SmartMailboxes", bundle: .module,
                comment: "Title of the alert before deleting a smart mailbox, with its name"),
            message: String(
                localized: "Its mail stays where it is. The smart mailbox goes from all your devices.",
                table: "SmartMailboxes", bundle: .module, comment: "What deleting a smart mailbox does"),
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: Self.cancel, style: .cancel))
        alert.addAction(
            UIAlertAction(
                title: String(
                    localized: "Delete", table: "SmartMailboxes", bundle: .module,
                    comment: "Button: deletes the smart mailbox"),
                style: .destructive
            ) { [weak self] _ in
                guard let self else { return }
                changes.run { [self] in
                    do {
                        try await store.delete(box.id)
                        deleted()
                    } catch {
                        showFailure(error)
                    }
                }
            })
        presenter()?.present(alert, animated: true)
    }

    private func present(_ draft: SmartMailboxDraft) async {
        let labelNames = await store.labelNames()
        let editor = SmartMailboxEditor(draft: draft, labelNames: labelNames) { [weak self] box, vips in
            self?.store(box, vips: vips)
        }
        presenter()?.present(UIHostingController(rootView: editor), animated: true)
    }

    private func store(_ box: SmartMailbox, vips: VIPList?) {
        changes.run { [self] in
            do {
                try await store.save(box, vips)
            } catch {
                showFailure(error)
            }
        }
    }

    private func showFailure(_ error: any Error) {
        let alert = UIAlertController(
            title: String(
                localized: "Couldn’t Save the Smart Mailbox", table: "SmartMailboxes", bundle: .module,
                comment: "Alert title when storing a smart mailbox failed"),
            message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(
            UIAlertAction(
                title: String(
                    localized: "OK", table: "SmartMailboxes", bundle: .module, comment: "Button: dismisses the alert"),
                style: .default))
        presenter()?.present(alert, animated: true)
    }
}
