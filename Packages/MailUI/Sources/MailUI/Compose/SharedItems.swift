public import Foundation
public import MailCore
import UniformTypeIdentifiers

/// Reads what another app shared, dropped or pasted into a `SharedContent`. The item providers belong to the main
/// actor, but each one loads and hands over its file on a queue of its own, so no file is read on the main actor. A
/// page from Safari's share sheet comes with its title (ShareScript.js), a link or text as itself, and anything else
/// as a file. Files are read only while the message stays within what Gmail accepts (`limit`), so a long video is
/// never loaded into the Share extension's small memory.
public enum SharedItems {
    /// What came, and whether some file was left out for its size.
    public struct Loaded: Sendable {
        public var content: SharedContent
        public var leftOutFiles: Bool
    }

    /// What to read: the title and texts that came beside the items, as a share sheet's do, and the items.
    public struct Request {
        public var title: String?
        public var texts: [String]
        public var providers: [NSItemProvider]

        public init(title: String? = nil, texts: [String] = [], providers: [NSItemProvider]) {
            self.title = title
            self.texts = texts
            self.providers = providers
        }
    }

    /// Whether the provider holds words to write in the message, a link or text the app wrote, rather than a file to
    /// attach: what its richest reading is.
    static func holdsWords(_ provider: NSItemProvider) -> Bool {
        switch readings(of: provider).first {
        case .link, .text: true
        case .page, .file, nil: false
        }
    }

    /// One way to read a provider.
    fileprivate enum Reading {
        /// The title and address ShareScript.js read from a page in Safari.
        case page
        case link
        /// Text the app wrote, which has no file name.
        case text
        case file(UTType)
    }

    /// The ways to read `provider`, the richest first; a reading that finds nothing falls to the next. A picture,
    /// video or PDF goes as a file even where the app also gives its address, as Safari does for a picture on a page,
    /// and so does a file's own address.
    private static func readings(of provider: NSItemProvider) -> [Reading] {
        let types = provider.registeredContentTypes
        let file = fileType(in: types).map(Reading.file)
        let isFile = types.contains { type in
            [.fileURL, .image, .audiovisualContent, .pdf].contains { type.conforms(to: $0) }
        }
        var readings: [Reading] = []
        if types.contains(.propertyList) { readings.append(.page) }
        if isFile, let file { readings.append(file) }
        if types.contains(where: isLink), !types.contains(where: { $0.conforms(to: .fileURL) }) {
            readings.append(.link)
        }
        if provider.suggestedName == nil, types.contains(where: { $0.conforms(to: .plainText) }) {
            readings.append(.text)
        }
        if !isFile, let file { readings.append(file) }
        return readings
    }

    /// A web address, not a file's.
    private static func isLink(_ type: UTType) -> Bool {
        type.conforms(to: .url) && !type.conforms(to: .fileURL)
    }

    /// The form a file goes in. A photo Photos also offers as JPEG goes as JPEG, which every mail app shows, as Mail
    /// sends photos; converting a HEIC here would decode the whole picture, more than an extension's memory holds.
    private static func fileType(in types: [UTType]) -> UTType? {
        types.first { $0.conforms(to: .jpeg) }
            ?? types.first { $0.conforms(to: .content) || $0.conforms(to: .data) } ?? types.first
    }

    enum Piece: Sendable {
        case page(title: String?, link: URL?)
        case text(String)
        case link(URL)
        case file(DraftAttachment)
        /// A file that would take the message past `limit`.
        case tooLarge
    }

    /// Reads one provider after another, each file read only once it fits beside the ones before it, so a share
    /// never holds more than the message can take: the Share extension's memory is small.
    public static func load(_ request: Request, limit: Int) async -> Loaded {
        var assembly = Assembly(request, limit: limit)
        for provider in request.providers {
            // Whatever the place no longer wants isn't read.
            guard !Task.isCancelled else { break }
            assembly.add(await piece(of: provider, skippingFirst: false, room: assembly.room))
        }
        return assembly.loaded
    }

    /// Asks every provider for what it holds at once, as a drop must before its handler returns: afterwards the app
    /// it came from may be gone. Each file is read while it fits in `limit` on its own; `Started.loaded` then takes
    /// them in order while they fit together.
    static func start(_ request: Request, limit: Int) -> Started {
        var started = Started(request: Request(title: request.title, texts: request.texts, providers: []), limit: limit)
        for provider in request.providers { started.start(provider) }
        return started
    }

    /// Reads under way, from `start`.
    struct Started {
        fileprivate var request: Request
        fileprivate let limit: Int
        fileprivate var reads: [(NSItemProvider, Reading?, PieceRead?)] = []

        /// Asks one more provider for what it holds, now.
        mutating func start(_ provider: NSItemProvider) {
            let first = readings(of: provider).first
            request.providers.append(provider)
            reads.append((provider, first, first.map { read($0, of: provider, room: limit) }))
        }

        /// Stops the reads, for a place that no longer wants what they find.
        func cancel() {
            for (_, _, read) in reads { read?.cancel() }
        }

        /// What came, in order, files while they fit together. A read that found nothing falls to the provider's next
        /// reading, now.
        func loaded() async -> Loaded {
            var assembly = Assembly(request, limit: limit)
            await withTaskCancellationHandler {
                for (provider, first, read) in reads {
                    guard !Task.isCancelled else { break }
                    if let piece = await read?.piece() {
                        assembly.add(piece)
                    } else if first != nil {
                        assembly.add(await SharedItems.piece(of: provider, skippingFirst: true, room: assembly.room))
                    }
                }
            } onCancel: { [pending = reads.compactMap(\.2)] in
                for read in pending { read.cancel() }
            }
            return assembly.loaded
        }
    }

    /// What the pieces make, as they come.
    private struct Assembly {
        private var content: SharedContent
        private var texts: [String]
        private var leftOut = false
        private let limit: Int

        init(_ request: Request, limit: Int) {
            content = SharedContent(title: request.title)
            texts = request.texts
            self.limit = limit
        }

        var room: Int { limit - content.files.reduce(0) { $0 + $1.size } }

        mutating func add(_ piece: Piece?) {
            switch piece {
            case .page(let title, let link):
                if content.title == nil { content.title = title }
                // Safari passes the title as the item's text too; the subject already says it.
                texts.removeAll { $0 == title }
                if let link { content.links.append(link) }
            case .text(let text): texts.append(text)
            case .link(let link): content.links.append(link)
            case .file(let file) where file.size <= room: content.files.append(file)
            case .file, .tooLarge: leftOut = true
            case nil: break
            }
        }

        var loaded: Loaded {
            var content = content
            content.texts = texts
            return Loaded(content: content, leftOutFiles: leftOut)
        }
    }

    /// What `provider` holds, read one way after another until one finds something; after the first, when a read
    /// already tried it.
    private static func piece(of provider: NSItemProvider, skippingFirst: Bool, room: Int) async -> Piece? {
        for reading in readings(of: provider).dropFirst(skippingFirst ? 1 : 0) {
            let read = read(reading, of: provider, room: room)
            let piece = await withTaskCancellationHandler {
                await read.piece()
            } onCancel: {
                read.cancel()
            }
            if let piece { return piece }
        }
        return nil
    }

    /// Starts reading `provider` one way, now.
    private static func read(_ reading: Reading, of provider: NSItemProvider, room: Int) -> PieceRead {
        let read = PieceRead()
        let progress: Progress =
            switch reading {
            case .page:
                provider.loadDataRepresentation(for: .propertyList) { data, _ in
                    read.deliver(data.flatMap(pageResults(in:)))
                }
            case .link:
                provider.loadObject(ofClass: URL.self) { url, _ in
                    // A link that turns out to name a file isn't words: the file reading after it takes it.
                    read.deliver(url.flatMap { $0.isFileURL ? nil : .link($0) })
                }
            case .text:
                provider.loadObject(ofClass: String.self) { text, _ in read.deliver(text.map(Piece.text)) }
            case .file(let type):
                file(of: provider, type: type, room: room) { read.deliver($0) }
            }
        read.started(progress)
        return read
    }

    /// The script's results. Safari hands over its dictionary keyed-archived, not as a plain property list.
    nonisolated private static func pageResults(in data: Data) -> Piece? {
        let item =
            try? NSKeyedUnarchiver.unarchivedObject(
                ofClasses: [NSDictionary.self, NSString.self], from: data) as? [String: Any]
        guard let results = item?[NSExtensionJavaScriptPreprocessingResultsKey] as? [String: String] else {
            return nil
        }
        let title = results["title"].flatMap { $0.isEmpty ? nil : $0 }
        return .page(title: title, link: results["url"].flatMap(URL.init(string:)))
    }

    /// Copies the provider's file as an attachment once it is known to fit in `room`, then calls `deliver`. The file
    /// is only there until the callback returns.
    nonisolated private static func file(
        of provider: NSItemProvider, type: UTType, room: Int, deliver: @escaping @Sendable (Piece?) -> Void
    ) -> Progress {
        let suggested = provider.suggestedName
        return provider.loadFileRepresentation(for: type, openInPlace: false) { url, _, _ in
            guard let url, let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
                return deliver(nil)
            }
            guard size <= room else { return deliver(.tooLarge) }
            guard let data = try? Data(contentsOf: url) else { return deliver(nil) }
            let fileType = UTType(filenameExtension: url.pathExtension) ?? type
            deliver(
                .file(
                    DraftAttachment(
                        filename: filename(suggested, for: url, type: fileType),
                        mimeType: fileType.preferredMIMEType ?? "application/octet-stream", data: data)))
        }
    }

    /// The name the app suggested, with the file's extension unless it already ends in it, and no slash a file
    /// system would read as a folder.
    nonisolated static func filename(_ suggested: String?, for url: URL, type: UTType) -> String {
        guard let suggested, !suggested.isEmpty else { return url.lastPathComponent }
        let name = suggested.replacingOccurrences(of: "/", with: "-")
        let pathExtension = url.pathExtension.isEmpty ? type.preferredFilenameExtension ?? "" : url.pathExtension
        guard !pathExtension.isEmpty,
            (name as NSString).pathExtension.lowercased() != pathExtension.lowercased()
        else { return name }
        return "\(name).\(pathExtension)"
    }
}
