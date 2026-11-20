import UIKit

/// After words are dropped into the message, a menu at their end asks how they go in: as text, as they landed, or
/// as a quote. Dismissing it keeps them as text.
final class DroppedTextChoice: NSObject {
    private weak var textView: UITextView?
    /// Makes the words at the range a quote, once they still read as they landed.
    private let quote: (NSRange) -> Void
    private lazy var menu = UIEditMenuInteraction(delegate: self)
    /// The words the menu asks about while it shows: where they are, and what they say, so an edit since leaves
    /// them alone.
    private var offered: (range: NSRange, words: String)?

    init(in textView: UITextView, quote: @escaping (NSRange) -> Void) {
        self.textView = textView
        self.quote = quote
        super.init()
        textView.addInteraction(menu)
    }

    /// Shows the menu at the end of the words dropped at `range`.
    func offer(_ range: NSRange) {
        guard let textView, NSMaxRange(range) <= textView.textStorage.length, range.length > 0,
            let end = textView.position(from: textView.beginningOfDocument, offset: NSMaxRange(range))
        else { return }
        offered = (range, textView.textStorage.attributedSubstring(from: range).string)
        let caret = textView.caretRect(for: end)
        menu.presentEditMenu(
            with: UIEditMenuConfiguration(identifier: nil, sourcePoint: CGPoint(x: caret.midX, y: caret.maxY)))
    }

    private func choose(quoting: Bool) {
        guard let (range, words) = offered, let textView, NSMaxRange(range) <= textView.textStorage.length,
            textView.textStorage.attributedSubstring(from: range).string == words
        else { return }
        offered = nil
        if quoting { quote(range) }
    }
}

extension DroppedTextChoice: UIEditMenuInteractionDelegate {
    func editMenuInteraction(
        _ interaction: UIEditMenuInteraction, menuFor configuration: UIEditMenuConfiguration,
        suggestedActions: [UIMenuElement]
    ) -> UIMenu? {
        UIMenu(children: [
            UIAction(
                title: String(
                    localized: "Text", table: "Compose", bundle: .module,
                    comment: "Keeps text dropped into the message as ordinary text"),
                image: UIImage(systemName: "text.alignleft")
            ) { [weak self] _ in self?.choose(quoting: false) },
            UIAction(
                title: String(
                    localized: "Quote", table: "Compose", bundle: .module,
                    comment: "Formatting: quotes the paragraph"),
                image: UIImage(systemName: "text.quote")
            ) { [weak self] _ in self?.choose(quoting: true) },
        ])
    }

    func editMenuInteraction(
        _ interaction: UIEditMenuInteraction, willDismissMenuFor configuration: UIEditMenuConfiguration,
        animator: any UIEditMenuInteractionAnimating
    ) {
        // An action runs before the menu goes; anything else that closes it keeps the words as text. Cleared after
        // the action has had its turn.
        animator.addCompletion { [weak self] in self?.offered = nil }
    }
}
