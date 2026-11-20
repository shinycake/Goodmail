import MailCore
import UIKit
import UniformTypeIdentifiers

/// Takes in links, text, pictures and files dragged in from another app, or pasted, for one place that writes a
/// message: the composer, or a chat's message field. Dropped on the place's own text, words land where the drop's
/// caret shows, through the text view's paste (`accept(in:)`); files from that drop, which text can't hold, are
/// attached. Dropped anywhere else on the place (`interaction`), everything is read the way the Share extension reads
/// a share (`SharedItems`) and handed to `receive` whole, whose words go where the writer's caret is.
final class ContentIntake: NSObject {
    /// How many more bytes of files the message can take.
    private let room: () -> Int
    /// Whether the place can take a drop now, as while it shows.
    private let accepts: () -> Bool
    /// Puts what was read into the message, saying when some file couldn't fit.
    private let receive: (SharedItems.Loaded) -> Void
    /// Files from one paste or drop on the text, gathered while UIKit hands its items over one by one, to be read
    /// together so one alert says if some didn't fit.
    private var pendingFiles: [NSItemProvider] = []
    /// Reading what came. Each removes itself when done; whatever is still reading when the place goes is cancelled.
    private var reads: [UUID: Task<Void, Never>] = [:]

    init(
        room: @escaping () -> Int, accepts: @escaping () -> Bool = { true },
        receive: @escaping (SharedItems.Loaded) -> Void
    ) {
        self.room = room
        self.accepts = accepts
        self.receive = receive
    }

    isolated deinit {
        for read in reads.values { read.cancel() }
    }

    /// The kinds of item a message can hold: words, links, and any file.
    static let types: [UTType] = [.text, .url, .data, .content]

    /// Lets `textView` take files as well as words, dropped or pasted, attaching the files.
    func accept(in textView: UITextView) {
        let current = textView.pasteConfiguration?.acceptableTypeIdentifiers ?? []
        textView.pasteConfiguration = UIPasteConfiguration(
            acceptableTypeIdentifiers: current + Self.types.map(\.identifier).filter { !current.contains($0) })
        textView.pasteDelegate = self
    }

    /// Takes drops anywhere on the view it is added to that its subviews didn't take.
    var interaction: UIDropInteraction { UIDropInteraction(delegate: self) }

    /// Reads `providers` whole and hands them to `receive`.
    private func read(_ providers: [NSItemProvider]) {
        let id = UUID()
        let request = SharedItems.Request(providers: providers)
        let limit = max(room(), 0)
        reads[id] = Task { [weak self] in
            let loaded = await SharedItems.load(request, limit: limit)
            guard let self else { return }
            reads[id] = nil
            guard !Task.isCancelled, !loaded.isEmpty else { return }
            receive(loaded)
        }
    }

    /// The items a drop brings from outside this app's own drags, such as a thread's row or a recipient, which carry
    /// their own object and mean something else here.
    private static func providers(in session: any UIDropSession) -> [NSItemProvider] {
        session.items.filter { $0.localObject == nil }.map(\.itemProvider).filter { provider in
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
        // UIKit hands a paste's items over in one go, so the read that follows takes them all.
        if pendingFiles.isEmpty {
            let id = UUID()
            reads[id] = Task { [weak self] in
                guard let self else { return }
                reads[id] = nil
                let files = pendingFiles
                pendingFiles = []
                read(files)
            }
        }
        pendingFiles.append(provider)
    }
}

extension ContentIntake: UIDropInteractionDelegate {
    func dropInteraction(_ interaction: UIDropInteraction, canHandle session: any UIDropSession) -> Bool {
        accepts() && !Self.providers(in: session).isEmpty
    }

    func dropInteraction(_ interaction: UIDropInteraction, sessionDidUpdate session: any UIDropSession)
        -> UIDropProposal
    {
        UIDropProposal(operation: accepts() ? .copy : .cancel)
    }

    func dropInteraction(_ interaction: UIDropInteraction, performDrop session: any UIDropSession) {
        read(Self.providers(in: session))
    }
}
