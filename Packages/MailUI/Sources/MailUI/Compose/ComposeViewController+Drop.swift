import MailCore
import UIKit

/// Links, text, pictures and files dragged in from another app, or pasted. Dropped on the message's text, words land
/// at the drop's caret; dropped anywhere else on the composer, at the writer's caret. Files are attached either way.
extension ComposeViewController {
    func acceptDrops() {
        intake.accept(in: bodyView)
        intake.wordsDropped = { [unowned self] in droppedText.offer($0) }
        view.addInteraction(intake.makeInteraction())
    }

    /// Puts what came into the message: a title as the subject when there is none yet, words where the caret is in
    /// the body, and files attached while they fit. A message that has stopped being written takes nothing.
    public func receive(_ loaded: SharedItems.Loaded) {
        loadViewIfNeeded()
        let content = loaded.content
        if viewModel.subject.isEmpty, !content.subject.isEmpty {
            subjectField.text = content.subject
            fieldChanged()
        }
        if !content.body.isEmpty { droppedText.offer(bodyView.writeDropped(content.body)) }
        var leftOut = loaded.leftOutFiles
        for file in content.files where !viewModel.attach(file) { leftOut = true }
        if !content.files.isEmpty {
            attachmentsView.show(viewModel.attachments)
            updateSendEnabled()
        }
        if leftOut { tooLarge() }
    }

    /// Makes the words dropped at `range` a quote of their own: on lines apart from the text around them, quoted one
    /// level deeper, with the caret after them to write on.
    func quoteDropped(_ range: NSRange) {
        let text = bodyView.textStorage.string as NSString
        var words = range
        // The spaces that kept them apart from the words around them aren't part of the quote.
        while words.length > 0, text.character(at: words.location) == 0x20 {
            words = NSRange(location: words.location + 1, length: words.length - 1)
        }
        while words.length > 0, text.character(at: NSMaxRange(words) - 1) == 0x20 { words.length -= 1 }
        guard words.length > 0 else { return }
        if NSMaxRange(words) < text.length, !Self.isLineBreak(text.character(at: NSMaxRange(words))) {
            breakLine(at: NSMaxRange(words))
        }
        if words.location > 0, !Self.isLineBreak(text.character(at: words.location - 1)) {
            breakLine(at: words.location)
            words.location += 1
        }
        bodyView.selectedRange = words
        applyFormatting(.quote(.increase))
        bodyView.selectedRange = NSRange(location: NSMaxRange(words), length: 0)
        repairTypingLayout()
    }

    private static func isLineBreak(_ character: unichar) -> Bool {
        character == 0x0A || character == 0x2029 || character == 0x2028
    }

    /// Starts a new paragraph at `location`, in the look of the text before it.
    private func breakLine(at location: Int) {
        let storage = bodyView.textStorage
        let attributes =
            storage.length == 0
            ? bodyView.typingAttributes : storage.attributes(at: max(location - 1, 0))
        replace(
            NSRange(location: location, length: 0), with: NSAttributedString(string: "\n", attributes: attributes),
            selection: NSRange(location: location + 1, length: 0))
    }
}
