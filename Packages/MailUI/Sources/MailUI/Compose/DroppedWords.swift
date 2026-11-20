import UIKit

/// Words dropped into text already written, kept apart from the words around them, as a word typed there would be: a
/// space where they'd otherwise run into a word, none where a space or line break already is.
enum DroppedWords {
    static func spaced(_ words: String, after previous: Character?, before next: Character?) -> String {
        var spaced = words
        if let previous, !previous.isWhitespace, spaced.first?.isWhitespace == false { spaced = " " + spaced }
        if let next, !next.isWhitespace, spaced.last?.isWhitespace == false { spaced += " " }
        return spaced
    }
}

extension UITextView {
    /// Writes dropped `words` over the selection as typing them would: in the paragraph's look, undoable, telling the
    /// delegate, and spaced from the words around them. Returns where they went.
    @discardableResult
    func writeDropped(_ words: String) -> NSRange {
        // Words still being composed, as in Japanese, are kept as they stand rather than replaced.
        unmarkText()
        let text = textStorage.string as NSString
        let location = min(selectedRange.location, text.length)
        let range = NSRange(location: location, length: min(selectedRange.length, text.length - location))
        let previous = range.location > 0 ? character(in: text, at: range.location - 1) : nil
        let next = NSMaxRange(range) < text.length ? character(in: text, at: NSMaxRange(range)) : nil
        let spaced = DroppedWords.spaced(words, after: previous, before: next)
        selectedRange = range
        insertText(spaced)
        return NSRange(location: range.location, length: (spaced as NSString).length)
    }

    private func character(in text: NSString, at index: Int) -> Character? {
        text.substring(with: text.rangeOfComposedCharacterSequence(at: index)).first
    }
}
