import MailCore
import UIKit

/// The To, Cc and Bcc fields: each shows its part of the view model's `Recipients`, and every change the writer
/// makes goes through the view model and is shown back.
extension ComposeViewController {
    func recipientField(_ role: Recipients.Role, accessory: UIView? = nil) -> RecipientField {
        let field = RecipientField(role: role, title: role.label, accessory: accessory)
        field.moveTargets = Recipients.Role.allCases.filter { $0 != role }.map { ($0, $0.moveTitle) }
        field.show(viewModel.recipients[role])
        field.offersSuggestions = { [weak self, weak field] key in
            self?.offersSuggestions(key, under: field) ?? false
        }
        field.onIntent = { [weak self, weak field] intent in
            guard let self, let field else { return }
            handle(intent, in: field)
        }
        return field
    }

    private func handle(_ intent: RecipientField.Intent, in field: RecipientField) {
        switch intent {
        case .type(let text):
            edit(field) { $0.type(text) }
            showSuggestions(for: field)
        case .deleteBackward:
            edit(field) { _ = $0.deleteBackward() }
        case .select(let index):
            field.becomeFirstResponder()
            edit(field) { $0.select(index) }
            hideSuggestions()
        case .remove(let index):
            edit(field) { $0.remove(at: index) }
        case .move(let dragged, let destination, let index):
            viewModel.recipients.move(dragged.index, from: dragged.role, to: destination, at: index)
            if destination != .to { showCopyFields() }
            for other in [toField, ccField, bccField] { other.show(viewModel.recipients[other.role]) }
            updateSendEnabled()
        case .commit:
            pressed(.returnKey, in: field)
        case .highlight(let step):
            moveHighlight(step, in: field)
        case .complete:
            pressed(.tab, in: field)
        case .endEditing:
            edit(field) {
                $0.commit()
                $0.deselect()
            }
            hideSuggestions()
        case .drop(let text):
            edit(field) { $0.type($0.typed + "," + text + ",") }
            // What was typed became tokens: a list found for it offers no one now.
            hideSuggestions()
        }
    }

    /// Makes `change` to the field's recipients and shows the result.
    func edit(_ field: RecipientField, _ change: (inout RecipientEntry) -> Void) {
        change(&viewModel.recipients[field.role])
        field.show(viewModel.recipients[field.role])
        updateSendEnabled()
    }

    /// Where Return goes from a field with nothing typed: the next visible one, then the subject.
    func next(after field: RecipientField) -> UIResponder {
        let copies = copyFields == .shown
        let order: [(RecipientField, Bool)] = [(toField, true), (ccField, copies), (bccField, copies)]
        guard let index = order.firstIndex(where: { $0.0 === field }) else { return subjectField }
        return order[(index + 1)...].first(where: \.1)?.0 ?? subjectField
    }
}

extension Recipients.Role {
    fileprivate var label: String {
        switch self {
        case .to: String(localized: "To:", table: "Compose", bundle: .module, comment: "Compose field label")
        case .cc: String(localized: "Cc:", table: "Compose", bundle: .module, comment: "Compose field label")
        case .bcc: String(localized: "Bcc:", table: "Compose", bundle: .module, comment: "Compose field label")
        }
    }

    /// The token menu's command that moves a recipient into this field.
    fileprivate var moveTitle: String {
        switch self {
        case .to:
            String(localized: "Move to To", table: "Compose", bundle: .module, comment: "Recipient menu")
        case .cc:
            String(localized: "Move to Cc", table: "Compose", bundle: .module, comment: "Recipient menu")
        case .bcc:
            String(localized: "Move to Bcc", table: "Compose", bundle: .module, comment: "Recipient menu")
        }
    }
}
