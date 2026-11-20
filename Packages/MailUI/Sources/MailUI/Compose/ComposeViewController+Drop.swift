import MailCore
import UIKit

/// Links, text, pictures and files dragged in from another app, or pasted. Dropped on the message's text, words land
/// at the drop's caret; dropped anywhere else on the composer, at the writer's caret. Files are attached either way.
extension ComposeViewController {
    func acceptDrops() {
        intake.accept(in: bodyView)
        view.addInteraction(intake.interaction)
    }

    /// Puts what came into the message: a title as the subject when there is none yet, words where the caret is in
    /// the body, and files attached while they fit.
    func receive(_ loaded: SharedItems.Loaded) {
        loadViewIfNeeded()
        let content = loaded.content
        if viewModel.subject.isEmpty, !content.subject.isEmpty {
            subjectField.text = content.subject
            fieldChanged()
        }
        if !content.body.isEmpty { write(content.body) }
        let fitting = content.files.filter { viewModel.attach($0) }
        if !fitting.isEmpty {
            attachmentsView.show(viewModel.attachments)
            updateSendEnabled()
        }
        if loaded.leftOutFiles || fitting.count < content.files.count { tooLarge() }
    }

    /// Writes `text` over the body's selection, as typing it would: in the paragraph's look, undoable, and saved as
    /// the rest of the message is.
    private func write(_ text: String) {
        let selection = bodyView.selectedRange
        let range = NSRange(
            location: min(selection.location, bodyView.textStorage.length),
            length: min(selection.length, max(bodyView.textStorage.length - selection.location, 0)))
        bodyView.selectedRange = range
        bodyView.insertText(text)
    }
}
