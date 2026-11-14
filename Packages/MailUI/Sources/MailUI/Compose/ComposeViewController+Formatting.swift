import UIKit

/// The body's formatting: the controls above the keyboard, the system's Format panel limited to what the message
/// can carry, and each change applied as one undoable edit.
extension ComposeViewController {
    var bodyFont: UIFont { .preferredFont(forTextStyle: .body) }

    func configureFormatting() {
        bodyView.inputAccessoryView = formattingBar
        bodyView.textLayoutManager?.delegate = quoteLayout
        // Styles and lists only: fonts, sizes and colors wouldn't survive in the HTML that is sent.
        typealias Component = UITextFormattingViewController.Component
        bodyView.textFormattingConfiguration = UITextFormattingViewController.Configuration(groups: [
            UITextFormattingViewController.ComponentGroup(components: [
                Component(componentKey: .fontAttributes, preferredSize: .regular),
                Component(componentKey: .listStyles, preferredSize: .regular),
            ])
        ])
        formattingBar.onCommand = { [weak self] command in self?.applyFormatting(command) }
        formattingBar.onLink = { [weak self] in self?.askForLink() }
    }

    func showFormatting() {
        formattingBar.show(currentFormatting)
    }

    private var currentFormatting: Formatting {
        Formatting(
            text: bodyView.textStorage, selection: bodyView.selectedRange,
            typingAttributes: bodyView.typingAttributes)
    }

    func applyFormatting(_ command: FormattingCommand) {
        let edit = command.edit(
            text: bodyView.textStorage, selection: bodyView.selectedRange,
            typingAttributes: bodyView.typingAttributes, font: bodyFont)
        if edit.range.length > 0 || edit.replacement.length > 0 {
            replace(edit.range, with: edit.replacement, selection: edit.selection)
        }
        bodyView.typingAttributes = edit.typingAttributes
        showFormatting()
    }

    /// Puts `text` in place of `range` as one step Undo takes back.
    private func replace(_ range: NSRange, with text: NSAttributedString, selection: NSRange) {
        let replaced = bodyView.textStorage.attributedSubstring(from: range)
        let selected = bodyView.selectedRange
        let typing = bodyView.typingAttributes
        bodyView.textStorage.replaceCharacters(in: range, with: text)
        bodyView.selectedRange = selection
        bodyView.typingAttributes = typing
        bodyView.undoManager?.registerUndo(withTarget: self) { controller in
            controller.replace(
                NSRange(location: range.location, length: text.length), with: replaced, selection: selected)
        }
        updateSendEnabled()
    }

    /// Asks for the address to link the selection to, starting from the link it already has.
    private func askForLink() {
        let current = currentFormatting.link
        let alert = UIAlertController(
            title: String(
                localized: "Link", table: "Compose", bundle: .module, comment: "Formatting: links the selection"),
            message: nil, preferredStyle: .alert)
        alert.addTextField { field in
            field.text = current?.absoluteString
            field.placeholder = "example.com"
            field.keyboardType = .URL
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
            field.clearButtonMode = .whileEditing
        }
        if current != nil {
            alert.addAction(
                UIAlertAction(
                    title: String(
                        localized: "Remove Link", table: "Compose", bundle: .module,
                        comment: "Formatting: unlinks the text"),
                    style: .destructive
                ) { [weak self] _ in self?.applyFormatting(.link(nil)) })
        }
        alert.addAction(
            UIAlertAction(
                title: String(
                    localized: "Cancel", table: "Compose", bundle: .module, comment: "Closes the link prompt"),
                style: .cancel))
        let done = UIAlertAction(
            title: String(localized: "Done", table: "Compose", bundle: .module, comment: "Applies the link"),
            style: .default
        ) { [weak self, weak alert] _ in
            guard let url = FormattingCommand.linkURL(from: alert?.textFields?.first?.text ?? "") else { return }
            self?.applyFormatting(.link(url))
        }
        alert.addAction(done)
        alert.preferredAction = done
        present(alert, animated: true)
    }
}
