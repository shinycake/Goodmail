import MailCore
import UIKit
import UniformTypeIdentifiers

/// Takes in links, text, pictures and files dragged in from another app, or pasted, for one place that writes a
/// message: the composer, or a chat's message field. Dropped on the place's own text, words land where the drop's
/// caret shows, through the text view's paste (`accept(in:)`); files from that drop, which text can't hold, are
/// attached. Dropped anywhere else on the place (`makeInteraction()`), everything is read the way the Share extension
/// reads a share (`SharedItems`) and handed to `receive` whole, whose words go where the writer's caret is. Reading
/// starts before UIKit's handler returns, as a drop requires, and finishes off the main actor.
final class ContentIntake: NSObject {
    /// How many more bytes of files the message can take.
    private let room: () -> Int
    /// Whether the place can take a drop now, as while it shows.
    private let accepts: () -> Bool
    /// Puts what was read into the message, saying when some file couldn't fit.
    private let receive: (SharedItems.Loaded) -> Void
    /// Files from one paste or drop on the text, gathered while UIKit hands its items over one by one, to be put in
    /// together so one alert says if some didn't fit. Only `gather` and `flush` change it.
    private var paste = Paste.idle
    /// Reading what came. Each removes itself when done; `cancel()` stops them all.
    private var reads: [UUID: Task<Void, Never>] = [:]

    /// Told where words dropped on the text landed, once they are in, so the place can offer to make them a quote.
    var wordsDropped: ((NSRange) -> Void)?
    /// A drop on the text under way, from its start until its words are combined. Only the text drop and paste
    /// delegate methods change it.
    private var textDrop = TextDrop.idle

    private enum TextDrop {
        case idle
        case dropping(UITextView)
    }

    private enum Paste {
        case idle
        /// Files held back from the text, already being read, put in once UIKit has handed over the paste's other
        /// items.
        case gathering(SharedItems.Started, flush: Task<Void, Never>)
    }

    init(
        room: @escaping () -> Int, accepts: @escaping () -> Bool = { true },
        receive: @escaping (SharedItems.Loaded) -> Void
    ) {
        self.room = room
        self.accepts = accepts
        self.receive = receive
    }

    isolated deinit {
        cancel()
    }

    /// The place stopped writing, as a composer closing or minimizing: what is still being read stays out of it, and
    /// its reading stops.
    func cancel() {
        if case .gathering(let started, let flush) = paste {
            started.cancel()
            flush.cancel()
        }
        paste = .idle
        for read in reads.values { read.cancel() }
        reads = [:]
    }

    /// The kinds of item a message can hold: words, links, and any file.
    static let types: [UTType] = [.text, .url, .data, .content]

    /// Lets `textView` take files as well as words, dropped or pasted, attaching the files.
    func accept(in textView: UITextView) {
        let current = textView.pasteConfiguration?.acceptableTypeIdentifiers ?? []
        textView.pasteConfiguration = UIPasteConfiguration(
            acceptableTypeIdentifiers: current + Self.types.map(\.identifier).filter { !current.contains($0) })
        textView.pasteDelegate = self
        textView.textDropDelegate = self
    }

    /// An interaction taking drops anywhere on the view it is added to that its subviews didn't take. The view owns
    /// it; it holds this intake weakly.
    func makeInteraction() -> UIDropInteraction { UIDropInteraction(delegate: self) }

    /// Waits for what `started` reads and hands it to `receive`.
    private func finish(_ started: SharedItems.Started) {
        let id = UUID()
        reads[id] = Task { [weak self] in
            let loaded = await started.loaded()
            guard let self else { return }
            reads[id] = nil
            guard !Task.isCancelled, !loaded.isEmpty else { return }
            receive(loaded)
        }
    }

    /// The items a drop brings that a message can hold.
    private static func providers(in session: any UIDropSession) -> [NSItemProvider] {
        session.items.map(\.itemProvider).filter { provider in
            types.contains { provider.hasItemConformingToTypeIdentifier($0.identifier) }
        }
    }
}

extension SharedItems.Loaded {
    /// Nothing came that a message could carry, nor anything left out.
    fileprivate var isEmpty: Bool { content.isEmpty && !leftOutFiles }
}

extension ContentIntake: UITextPasteDelegate {
    /// Words take the text view's own way in, at the drop's caret or the selection; a file is held back to attach.
    func textPasteConfigurationSupporting(
        _ textPasteConfigurationSupporting: any UITextPasteConfigurationSupporting, transform item: any UITextPasteItem
    ) {
        let provider = item.itemProvider
        guard !SharedItems.holdsWords(provider) else { return item.setDefaultResult() }
        item.setNoResult()
        gather(provider)
    }

    /// Puts the items' words together as UIKit would, noting where a drop's words land: they go in once this returns.
    func textPasteConfigurationSupporting(
        _ textPasteConfigurationSupporting: any UITextPasteConfigurationSupporting,
        combineItemAttributedStrings itemStrings: [NSAttributedString], for textRange: UITextRange
    ) -> NSAttributedString {
        let combined = NSMutableAttributedString()
        for string in itemStrings { combined.append(string) }
        guard case .dropping(let textView) = textDrop, combined.length > 0 else { return combined }
        textDrop = .idle
        let landed = NSRange(
            location: textView.offset(from: textView.beginningOfDocument, to: textRange.start), length: combined.length)
        let id = UUID()
        reads[id] = Task { [weak self] in
            guard let self, !Task.isCancelled else { return }
            reads[id] = nil
            wordsDropped?(landed)
        }
        return combined
    }

    /// Starts reading a file held back from the text, to put in with the rest of the paste's files.
    private func gather(_ provider: NSItemProvider) {
        switch paste {
        case .idle:
            var started = SharedItems.start(SharedItems.Request(providers: []), limit: max(room(), 0))
            started.start(provider)
            // UIKit hands a paste's items over in one go, so the flush, which runs after it, takes them all.
            paste = .gathering(started, flush: Task { [weak self] in self?.flush() })
        case .gathering(var started, let flush):
            started.start(provider)
            paste = .gathering(started, flush: flush)
        }
    }

    private func flush() {
        guard case .gathering(let started, _) = paste else { return }
        paste = .idle
        finish(started)
    }
}

extension ContentIntake: UITextDropDelegate {
    func textDroppableView(
        _ textDroppableView: any UIView & UITextDroppable, willPerformDrop drop: any UITextDropRequest
    ) {
        // Text moved within the same text view stays as it was.
        guard let textView = textDroppableView as? UITextView, !textView.isTextDragActive else { return }
        textDrop = .dropping(textView)
    }

    func textDroppableView(
        _ textDroppableView: any UIView & UITextDroppable, dropSessionDidEnd session: any UIDropSession
    ) {
        textDrop = .idle
    }

    /// The text takes words dropped from anywhere, including this app's own text, but none of this app's own other
    /// drags, such as a thread's row, which opens a window.
    func textDroppableView(
        _ textDroppableView: any UIView & UITextDroppable, proposalForDrop drop: any UITextDropRequest
    ) -> UITextDropProposal {
        let own = drop.dropSession.items.contains { $0.localObject != nil && !SharedItems.holdsWords($0.itemProvider) }
        return own ? UITextDropProposal(operation: .cancel) : drop.suggestedProposal
    }
}

extension ContentIntake: UIDropInteractionDelegate {
    /// Only drops from other apps: this app's own drags, such as text from a message or a thread's row, mean
    /// something else when let go away from a text.
    func dropInteraction(_ interaction: UIDropInteraction, canHandle session: any UIDropSession) -> Bool {
        session.localDragSession == nil && accepts() && !Self.providers(in: session).isEmpty
    }

    func dropInteraction(_ interaction: UIDropInteraction, sessionDidUpdate session: any UIDropSession)
        -> UIDropProposal
    {
        UIDropProposal(operation: accepts() ? .copy : .cancel)
    }

    func dropInteraction(_ interaction: UIDropInteraction, performDrop session: any UIDropSession) {
        finish(
            SharedItems.start(SharedItems.Request(providers: Self.providers(in: session)), limit: max(room(), 0)))
    }
}
