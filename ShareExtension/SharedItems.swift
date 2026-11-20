import Foundation
import MailCore
import UniformTypeIdentifiers

/// Reads what another app shared into a `SharedContent`. The item providers belong to the main actor, but each one
/// loads and hands over its file on a queue of its own, so no file is read on the main actor. A page from Safari comes with its title
/// (ShareScript.js), a link or text as itself, and anything else as a file. Files are read only while the message
/// stays within what Gmail accepts (`limit`), so a long video is never loaded into the extension's small memory.
enum SharedItems {
    /// What came, and whether some file was left out for its size.
    struct Loaded {
        var content: SharedContent
        var leftOutFiles: Bool
    }

    /// The parts of the extension's items.
    struct Request {
        var title: String?
        var texts: [String]
        var providers: [NSItemProvider]

        init(_ items: [NSExtensionItem]) {
            title = items.lazy.compactMap { $0.attributedTitle?.string }.first { !$0.isEmpty }
            texts = items.compactMap { $0.attributedContentText?.string }
            providers = items.flatMap { $0.attachments ?? [] }
        }
    }

    private enum Piece: Sendable {
        case page(title: String?, link: URL?)
        case text(String)
        case link(URL)
        case file(DraftAttachment)
        /// A file that would take the message past `limit`.
        case tooLarge
    }

    static func load(_ request: Request, limit: Int) async -> Loaded {
        var content = SharedContent(title: request.title)
        var texts = request.texts
        var leftOut = false
        for provider in request.providers {
            let room = limit - content.files.reduce(0) { $0 + $1.size }
            switch await piece(of: provider, room: room) {
            case .page(let title, let link):
                if content.title == nil { content.title = title }
                // Safari passes the title as the item's text too; the subject already says it.
                texts.removeAll { $0 == title }
                if let link { content.links.append(link) }
            case .text(let text): texts.append(text)
            case .link(let link): content.links.append(link)
            case .file(let file): content.files.append(file)
            case .tooLarge: leftOut = true
            case nil: continue
            }
        }
        content.texts = texts
        return Loaded(content: content, leftOutFiles: leftOut)
    }

    /// What one provider holds, in the order an app's richest form comes first: Safari's page, a link, text the
    /// app wrote (which has no file name), then a file of any kind.
    private static func piece(of provider: NSItemProvider, room: Int) async -> Piece? {
        let types = provider.registeredContentTypes
        if types.contains(.propertyList), let page = await page(from: provider) { return page }
        if types.contains(where: { $0.conforms(to: .url) && !$0.conforms(to: .fileURL) }),
            let url = await object(URL.self, from: provider)
        {
            return url.isFileURL ? await file(of: provider, types: types, room: room) : .link(url)
        }
        if provider.suggestedName == nil, types.contains(where: { $0.conforms(to: .plainText) }),
            let text = await object(String.self, from: provider)
        {
            return .text(text)
        }
        return await file(of: provider, types: types, room: room)
    }

    /// The title and address ShareScript.js read from the page in Safari.
    private static func page(from provider: NSItemProvider) async -> Piece? {
        await withCheckedContinuation { continuation in
            _ = provider.loadDataRepresentation(for: .propertyList) { data, _ in
                continuation.resume(returning: data.flatMap(pageResults(in:)))
            }
        }
    }

    /// The script's results, from the property list Safari hands over.
    nonisolated private static func pageResults(in data: Data) -> Piece? {
        // Unsafe only for the format out-pointer, which is nil: nothing is written through it.
        let item = try? unsafe PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        guard let results = item?[NSExtensionJavaScriptPreprocessingResultsKey] as? [String: String] else {
            return nil
        }
        let title = results["title"].flatMap { $0.isEmpty ? nil : $0 }
        return .page(title: title, link: results["url"].flatMap(URL.init(string:)))
    }

    private static func object<T: _ObjectiveCBridgeable & Sendable>(_ type: T.Type, from provider: NSItemProvider)
        async -> T? where T._ObjectiveCType: NSItemProviderReading
    {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: type) { object, _ in continuation.resume(returning: object) }
        }
    }

    /// The provider's file as an attachment, read only when it fits in `room`. A photo Photos also offers as JPEG
    /// goes as JPEG, which every mail app shows, as Mail sends photos; converting a HEIC here would decode the whole
    /// picture, more than an extension's memory holds.
    private static func file(of provider: NSItemProvider, types: [UTType], room: Int) async -> Piece? {
        let type =
            types.first { $0.conforms(to: .jpeg) } ?? types.first {
                $0.conforms(to: .content) || $0.conforms(to: .data)
            }
            ?? types.first
        guard let type else { return nil }
        let suggested = provider.suggestedName
        return await withCheckedContinuation { continuation in
            // The file is only there until the callback returns.
            _ = provider.loadFileRepresentation(for: type, openInPlace: false) { url, _, _ in
                guard let url, let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
                    return continuation.resume(returning: nil)
                }
                guard size <= room else { return continuation.resume(returning: .tooLarge) }
                guard let data = try? Data(contentsOf: url) else { return continuation.resume(returning: nil) }
                let fileType = UTType(filenameExtension: url.pathExtension) ?? type
                continuation.resume(
                    returning: .file(
                        DraftAttachment(
                            filename: filename(suggested, for: url, type: fileType),
                            mimeType: fileType.preferredMIMEType ?? "application/octet-stream", data: data)))
            }
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
