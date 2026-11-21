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

    /// Starts a new message with what was dropped on a mail window, once its own window shows it: the words go at the
    /// top, above the signature, where a new message's caret starts, as they do in the sheet.
    public func start(with loaded: SharedItems.Loaded) {
        loadViewIfNeeded()
        bodyView.selectedRange = NSRange(location: 0, length: 0)
        receive(loaded)
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
    /// level deeper, with the caret after them to write on. The spaces that kept them apart from the words around
    /// them become those line breaks.
    func quoteDropped(_ range: NSRange) {
        let text = bodyView.textStorage.string as NSString
        let isSpace = { (index: Int) in text.character(at: index) == 0x20 }
        var words = range
        while words.length > 0, isSpace(words.location) {
            words = NSRange(location: words.location + 1, length: words.length - 1)
        }
        while words.length > 0, isSpace(NSMaxRange(words) - 1) { words.length -= 1 }
        guard words.length > 0 else { return }
        // The spaces on either side, out to the words around them.
        var after = NSMaxRange(words)
        while after < text.length, isSpace(after) { after += 1 }
        var before = words.location
        while before > 0, isSpace(before - 1) { before -= 1 }
        // The end first, so the start's place holds.
        if after < text.length, !Self.isLineBreak(text.character(at: after)) {
            breakLine(replacing: NSRange(location: NSMaxRange(words), length: after - NSMaxRange(words)))
        }
        if before > 0, !Self.isLineBreak(text.character(at: before - 1)) {
            breakLine(replacing: NSRange(location: before, length: words.location - before))
            words.location = before + 1
        }
        bodyView.selectedRange = words
        applyFormatting(.quote(.increase))
        bodyView.selectedRange = NSRange(location: NSMaxRange(words), length: 0)
        repairTypingLayout()
    }

    private static func isLineBreak(_ character: unichar) -> Bool {
        character == 0x0A || character == 0x2029 || character == 0x2028
    }

    /// Starts a new paragraph in place of `range`, in the look of the text before it.
    private func breakLine(replacing range: NSRange) {
        let storage = bodyView.textStorage
        let attributes =
            storage.length == 0
            ? bodyView.typingAttributes : storage.attributes(at: max(range.location - 1, 0))
        replace(
            range, with: NSAttributedString(string: "\n", attributes: attributes),
            selection: NSRange(location: range.location + 1, length: 0))
    }
}
