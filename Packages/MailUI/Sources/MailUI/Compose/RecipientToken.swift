import MailCore
import UIKit

/// One recipient in a field, as a tinted pill with the person's name. A tap selects it and opens its menu, which
/// names the address and offers Copy, a move to another field and Remove. An address that can't be sent to is red.
final class RecipientToken: ConfiguredButton {
    let contact: Contact

    init(contact: Contact, menu: UIMenu) {
        self.contact = contact
        super.init(frame: .zero)
        var configuration = UIButton.Configuration.plain()
        configuration.cornerStyle = .capsule
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 3, leading: 9, bottom: 3, trailing: 9)
        configuration.titleLineBreakMode = .byTruncatingTail
        configuration.title = contact.displayName
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
            var attributes = $0
            attributes.font = .preferredFont(forTextStyle: .body)
            return attributes
        }
        self.configuration = configuration
        tintColor = contact.hasValidAddress ? nil : .systemRed
        configurationUpdateHandler = { button in
            // Selected, the pill fills in, as Delete is about to remove it.
            let tint = button.tintColor ?? .tintColor
            button.configuration?.baseForegroundColor = button.isSelected ? .white : tint
            button.configuration?.background.backgroundColor =
                button.isSelected ? tint : tint.withAlphaComponent(0.14)
        }
        self.menu = menu
        showsMenuAsPrimaryAction = true
        accessibilityLabel = contact.displayName
        accessibilityValue =
            contact.hasValidAddress
            ? contact.address
            : String(
                localized: "\(contact.address), not a valid address", table: "Compose", bundle: .module,
                comment: "VoiceOver: a recipient whose address can't be sent to")
        largeContentTitle = contact.displayName
        showsLargeContentViewer = true
        addInteraction(UILargeContentViewerInteraction())
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }
}

/// A token being dragged, so a drop in another field moves it rather than copying its text.
struct DraggedRecipient {
    let role: Recipients.Role
    let index: Int
}

/// A text field that reports Delete when it has nothing left to delete, so the field can select and remove tokens.
final class RecipientTextField: UITextField {
    var onDeleteWhenEmpty: () -> Void = {}
    /// Whether people are offered under the field: Up, Down and Tab then go to them, not to the text or the next
    /// field.
    var offersSuggestions: () -> Bool = { false }
    var onSuggestionKey: (SuggestionKey) -> Void = { _ in }

    enum SuggestionKey {
        case up
        case down
        case tab
    }

    override var keyCommands: [UIKeyCommand]? {
        guard offersSuggestions() else { return super.keyCommands }
        return [UIKeyCommand.inputUpArrow, UIKeyCommand.inputDownArrow, "\t"].map { input in
            let command = UIKeyCommand(input: input, modifierFlags: [], action: #selector(suggestionKey(_:)))
            command.wantsPriorityOverSystemBehavior = true
            return command
        }
    }

    @objc private func suggestionKey(_ command: UIKeyCommand) {
        switch command.input {
        case UIKeyCommand.inputUpArrow: onSuggestionKey(.up)
        case UIKeyCommand.inputDownArrow: onSuggestionKey(.down)
        default: onSuggestionKey(.tab)
        }
    }

    override func deleteBackward() {
        guard text?.isEmpty ?? true else { return super.deleteBackward() }
        onDeleteWhenEmpty()
    }
}
