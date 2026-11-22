import MailCore
public import UIKit

/// The body's formatting: the controls above the keyboard or along the window's bottom, the system's Format panel
/// limited to what the message can carry, and each change applied as one undoable edit.
extension ComposeViewController {
    var bodyFont: UIFont { .preferredFont(forTextStyle: .body) }

    func configureFormatting() {
        // Above the keyboard, as `formattingPlacement` starts, until the window's style says otherwise.
        bodyView.inputAccessoryView = formattingBar
        placeFormattingBar()
        registerForTraitChanges([InteractionStyleTrait.self]) { (self: Self, _) in self.placeFormattingBar() }
        // Styles and lists only: the bar's sizes and colors are the ones the HTML that is sent carries; the panel's
        // fonts and free sizes and colors would be lost. Mac Catalyst has no such panel, so the bar is all it has.
        #if !targetEnvironment(macCatalyst)
            typealias Component = UITextFormattingViewController.Component
            bodyView.textFormattingConfiguration = UITextFormattingViewController.Configuration(groups: [
                UITextFormattingViewController.ComponentGroup(components: [
                    Component(componentKey: .fontAttributes, preferredSize: .regular),
                    Component(componentKey: .listStyles, preferredSize: .regular),
                ])
            ])
        #endif
        formattingBar.onCommand = { [weak self] command in self?.applyFormatting(command) }
        formattingBar.onLink = { [weak self] in self?.askForLink() }
        formattingBar.onMoreColors = { [weak self] in self?.pickColor() }
    }

    func showFormatting() {
        formattingBar.show(currentFormatting)
    }

    var currentFormatting: Formatting {
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

    /// Typing goes in with the layout of the paragraph it joins. Remembers where, to settle it once it lands.
    func prepareTypedLayout(replacing range: NSRange, with text: String) {
        bodyView.typingAttributes = FormattingCommand.typingLayout(
            in: bodyView.textStorage, at: range, typingAttributes: bodyView.typingAttributes)
        typedRange = NSRange(location: range.location, length: (text as NSString).length)
    }

    /// UIKit takes a moved caret's typing attributes from the character before it, without the quote, size and
    /// color it carries. Puts back the layout of the caret's line and the size and color of the text it continues,
    /// so the controls, Return and the next keystroke all see them.
    func repairTypingLayout() {
        guard bodyView.selectedRange.length == 0 else { return }
        let typing = FormattingCommand.typingLayout(
            in: bodyView.textStorage, at: bodyView.selectedRange, typingAttributes: bodyView.typingAttributes)
        bodyView.typingAttributes = RichText.typingRun(
            in: bodyView.textStorage, at: bodyView.selectedRange.location, typingAttributes: typing)
    }

    /// Lays out the paragraphs the last edit touched as one each, reading the way their text now does, draws what it
    /// put in in the colors that are sent, and redraws the quote bars, which typing can move without changing the
    /// body's height. Text still being composed, such as a word in a Japanese keyboard, settles once it is chosen.
    func settleTypedLayout() {
        bodyView.setNeedsLayout()
        guard bodyView.markedTextRange == nil, let range = typedRange else { return }
        typedRange = nil
        let selection = bodyView.selectedRange
        bodyView.textStorage.settleLayout(around: range, font: bodyFont)
        bodyView.textStorage.settleColors(in: range)
        bodyView.selectedRange = selection
    }

    /// Puts `text` in place of `range` as one step Undo takes back.
    func replace(_ range: NSRange, with text: NSAttributedString, selection: NSRange) {
        let replaced = bodyView.textStorage.attributedSubstring(from: range)
        let selected = bodyView.selectedRange
        let typing = bodyView.typingAttributes
        bodyView.textStorage.replaceCharacters(in: range, with: text)
        bodyView.selectedRange = selection
        bodyView.typingAttributes = typing
        bodyView.setNeedsLayout()
        bodyView.undoManager?.registerUndo(withTarget: self) { controller in
            controller.replace(
                NSRange(location: range.location, length: text.length), with: replaced, selection: selected)
        }
        updateSendEnabled()
    }

    /// Asks for the address to link the selection to, starting from the link it already has.
    func askForLink() {
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

    /// Opens the system's color picker on the selection's color, half height so the text it colors stays in view.
    private func pickColor() {
        let picker = UIColorPickerViewController()
        picker.title = String(
            localized: "Text Color", table: "Formatting", bundle: .module, comment: "Formatting: the text color menu")
        picker.supportsAlpha = false
        if case .ink(let ink) = currentFormatting.color { picker.selectedColor = UIColor(ink.color) }
        picker.delegate = self
        picker.sheetPresentationController?.detents = [.medium(), .large()]
        picker.sheetPresentationController?.prefersGrabberVisible = true
        present(picker, animated: true)
    }
}

extension ComposeViewController: UIColorPickerViewControllerDelegate {
    /// Colors the selection with each color the writer settles on, not every step of a drag. The picker then shows
    /// the color as it is sent, which may be a little deeper or lighter than the one picked.
    public func colorPickerViewController(
        _ picker: UIColorPickerViewController, didSelect color: UIColor, continuously: Bool
    ) {
        guard !continuously else { return }
        let (red, green, blue, _) = color.rgba
        let chosen = RichText.TextColor(
            MailCore.RGBColor(fractionalRed: Double(red), green: Double(green), blue: Double(blue)))
        applyFormatting(.color(chosen))
        picker.selectedColor = chosen.color
    }

    public func colorPickerViewControllerDidFinish(_ picker: UIColorPickerViewController) {
        bodyView.becomeFirstResponder()
    }
}
