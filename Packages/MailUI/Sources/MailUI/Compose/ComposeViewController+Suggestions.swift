import MailCore
import UIKit

/// The people offered under the recipient being typed: listed under its field, one highlighted, which Up and Down
/// move and Return or Tab adds, and any of them added with a click or a tap.
extension ComposeViewController {
    /// Whether people are offered under a recipient field, and which.
    enum Suggesting {
        case hidden
        case shown(SuggestionList, under: RecipientField)
    }

    /// Whether people are offered under `field` now.
    func isSuggesting(under field: RecipientField?) -> Bool {
        guard case .shown(_, let under) = suggesting else { return false }
        return under === field
    }

    /// Looks up the people matching what is being typed in `field` and lists them right under it.
    func showSuggestions(for field: RecipientField) {
        suggestionLookup?.cancel()
        let role = field.role
        suggestionLookup = Task { [weak self, weak field] in
            guard let self, let field else { return }
            let contacts = await viewModel.suggestions(for: role)
            guard !Task.isCancelled else { return }
            show(SuggestionList(contacts), under: field)
        }
    }

    func hideSuggestions() {
        suggestionLookup?.cancel()
        show(nil, under: nil)
    }

    /// Up or Down in `field` moves the highlight among the people offered under it.
    func moveHighlight(_ step: SuggestionList.Step, in field: RecipientField) {
        guard case .shown(var list, let under) = suggesting, under === field else { return }
        list.move(step)
        suggesting = .shown(list, under: under)
        showHighlight(of: list)
    }

    /// Which key asks to add someone from the list: Return only the person picked with Up or Down, so a typed
    /// address that also matches someone else stays as typed; Tab the picked one or else the first.
    enum CompletionKey {
        case returnKey
        case tab
    }

    /// Adds the person `key` asks for from the list under `field`. Returns whether it did.
    func completeWithHighlighted(in field: RecipientField, by key: CompletionKey) -> Bool {
        guard case .shown(let list, let under) = suggesting, under === field else { return false }
        let person: Contact? =
            switch key {
            case .returnKey: list.picked
            case .tab: list.tabChoice
            }
        guard let person else { return false }
        edit(field) { $0.complete(with: person) }
        hideSuggestions()
        return true
    }

    /// Lists `list` under `field`, or hides the list for `nil`. The one place `suggesting` is set from a lookup.
    private func show(_ list: SuggestionList?, under field: RecipientField?) {
        let shown: Int
        switch suggesting {
        case .hidden: shown = 0
        case .shown(let old, _): shown = old.contacts.count
        }
        for view in suggestionRows.arrangedSubviews { view.removeFromSuperview() }
        suggestionRows.removeFromSuperview()
        guard let list, let field, let row = [toField: toRow, ccField: ccRow, bccField: bccRow][field] ?? nil,
            let index = fields.arrangedSubviews.firstIndex(of: row)
        else {
            suggesting = .hidden
            suggestionRows.isHidden = true
            return
        }
        suggesting = .shown(list, under: field)
        for contact in list.contacts { suggestionRows.addArrangedSubview(button(for: contact, in: field)) }
        showHighlight(of: list)
        fields.insertArrangedSubview(suggestionRows, at: index + 1)
        suggestionRows.isHidden = false
        // The list appears under the field without moving VoiceOver off it, so say how many there are, after the
        // letter just typed is read and only when the number changes.
        if list.contacts.count != shown {
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
