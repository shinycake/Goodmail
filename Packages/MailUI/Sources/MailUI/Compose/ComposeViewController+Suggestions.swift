import MailCore
import UIKit

/// The people offered under the recipient being typed: listed under its field, one highlighted, which Up and Down
/// move and Return or Tab adds, and any of them added with a click or a tap. `suggestions` holds what is offered; this
/// draws it and does what its keys ask.
extension ComposeViewController {
    func makeSuggestions() -> RecipientSuggestions {
        RecipientSuggestions(
            draw: { [weak self] now, before in self?.show(now, replacing: before) },
            press: { [weak self] key, field in self?.press(key, in: field) })
    }

    /// What is typed in `field` after its tokens.
    private func typed(in field: RecipientField) -> String {
        viewModel.recipients[field.role].typed
    }

    /// Whether `key` in `field` goes to the people offered under it rather than to the text or the next field.
    func offersSuggestions(_ key: RecipientTextField.SuggestionKey, under field: RecipientField?) -> Bool {
        guard let field else { return false }
        return suggestions.takes(key, under: field, typed: typed(in: field))
    }

    /// Whether people found for what is typed in `field` are offered under it now.
    func isSuggesting(under field: RecipientField?) -> Bool {
        guard let field else { return false }
        return suggestions.current(under: field, typed: typed(in: field)) != nil
    }

    /// Looks up the people matching what is being typed in `field` and lists them right under it.
    func showSuggestions(for field: RecipientField) {
        let role = field.role
        suggestions.look(for: typed(in: field), under: field) { [weak self] in
            await self?.viewModel.suggestions(for: role) ?? []
        }
    }

    func hideSuggestions() {
        suggestions.hide()
    }

    /// Up or Down in `field` moves the highlight among the people offered under it.
    func moveHighlight(_ step: SuggestionList.Step, in field: RecipientField) {
        suggestions.move(step, under: field, typed: typed(in: field))
    }

    /// Return or Tab in `field`: waits for a lookup under way when its answer decides what the key does, else does it.
    func pressed(_ key: RecipientSuggestions.CompletionKey, in field: RecipientField) {
        guard !suggestions.wait(key, under: field) else { return }
        press(key, in: field)
    }

    /// Adds the person `key` asks for from the list found for what is typed in `field`. Without one, Return makes
    /// tokens of what is typed, or goes on to the next field when nothing is, and Tab goes on to the next field.
    private func press(_ key: RecipientSuggestions.CompletionKey, in field: RecipientField) {
        let list = suggestions.current(under: field, typed: typed(in: field))
        let person: Contact? =
            switch key {
            case .returnKey: list?.picked
            case .tab: list?.tabChoice
            }
        if let person {
            edit(field) { $0.complete(with: person) }
            return hideSuggestions()
        }
        switch key {
        case .returnKey:
            let wasEmpty = typed(in: field).isEmpty
            edit(field) { $0.commit() }
            hideSuggestions()
            if wasEmpty { next(after: field).becomeFirstResponder() }
        case .tab:
            hideSuggestions()
            next(after: field).becomeFirstResponder()
        }
    }

    /// Lists `shown` under its field in place of `old`, or hides the list for `nil`. The same people under the same
    /// field only move their highlight.
    private func show(
        _ shown: RecipientSuggestions.OnShow?, replacing old: RecipientSuggestions.OnShow?
    ) {
        if let shown, let old, shown.field === old.field, shown.list.contacts == old.list.contacts {
            return showHighlight(of: shown.list)
        }
        for view in suggestionRows.arrangedSubviews { view.removeFromSuperview() }
        suggestionRows.removeFromSuperview()
        guard let shown, let row = [toField: toRow, ccField: ccRow, bccField: bccRow][shown.field] ?? nil,
            let index = fields.arrangedSubviews.firstIndex(of: row)
        else {
            suggestionRows.isHidden = true
            return
        }
        let (list, field) = shown
        for contact in list.contacts { suggestionRows.addArrangedSubview(button(for: contact, in: field)) }
        showHighlight(of: list)
        fields.insertArrangedSubview(suggestionRows, at: index + 1)
        suggestionRows.isHidden = false
        // The list appears under the field without moving VoiceOver off it, so say how many there are, after the
        // letter just typed is read and only when the number changes.
        if list.contacts.count != old?.list.contacts.count ?? 0 {
            SystemAccessibility.announce(
                String(
                    localized: "\(list.contacts.count) suggestions", table: "Compose", bundle: .module,
                    comment: "VoiceOver: how many recipients are suggested under the field"),
                queued: true)
        }
    }

    private func showHighlight(of list: SuggestionList) {
        for (index, row) in suggestionRows.arrangedSubviews.enumerated() {
            (row as? UIButton)?.isSelected = list.highlight == .on(index)
        }
    }

    /// A row of the list: a click or a tap adds the person.
    private func button(for contact: Contact, in field: RecipientField) -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.title = contact.name ?? contact.address
        configuration.subtitle = contact.name == nil ? nil : contact.address
        configuration.titleAlignment = .leading
        configuration.baseForegroundColor = .label
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)
        configuration.subtitleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
            var attributes = $0
            attributes.foregroundColor = .secondaryLabel
            return attributes
        }
        let button = ConfiguredButton(
            configuration: configuration,
            primaryAction: UIAction { [weak self, weak field] _ in
                guard let self, let field else { return }
                edit(field) { $0.complete(with: contact) }
                hideSuggestions()
            })
        button.contentHorizontalAlignment = .leading
        // The highlighted person, whom Return or Tab adds, is filled in.
        button.configurationUpdateHandler = { button in
            var configuration = button.configuration
            configuration?.background.backgroundColor = button.isSelected ? .tertiarySystemFill : .clear
            button.configuration = configuration
        }
        return button
    }
}
