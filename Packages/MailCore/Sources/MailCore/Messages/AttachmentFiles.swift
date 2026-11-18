public import Foundation

/// Attachment files kept on disk, one folder per message part, `<root>/<account>/<message>-<part>/<file>`: the layout
/// the cache cap trims (ADR-007). Each use stamps the file's modification date, which the cap evicts by, least
/// recently used first.
///
/// Inline images go through it as well as the attachments the reader opens, so a body's `cid:` images download once
/// and show offline from then on.
public struct AttachmentFiles: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// Where the part's file is kept, named as the sender named it.
    public func url(for attachment: Attachment, in message: Message.ID) -> URL {
        root.appending(path: message.accountID.rawValue, directoryHint: .isDirectory)
            .appending(path: "\(message.messageID)-\(attachment.id)", directoryHint: .isDirectory)
            .appending(path: Self.safeFilename(attachment.filename))
    }

    /// The part's file, stamped as used `now`, or nil when it isn't kept.
    @concurrent
    public func cachedFile(for attachment: Attachment, in message: Message.ID, at now: Date = .now) async -> URL? {
        let url = url(for: attachment, in: message)
        return touch(url, at: now) ? url : nil
    }

    /// The part's data, stamped as used `now`, or nil when it isn't kept.
    @concurrent
    public func cachedData(for attachment: Attachment, in message: Message.ID, at now: Date = .now) async -> Data? {
        let url = url(for: attachment, in: message)
        return touch(url, at: now) ? try? Data(contentsOf: url) : nil
    }

    /// Keeps the part's data, and returns its file.
    @concurrent
    @discardableResult
    public func keep(_ data: Data, for attachment: Attachment, in message: Message.ID) async throws -> URL {
        let url = url(for: attachment, in: message)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Stamps the file as used now, and says whether there is one.
    private func touch(_ url: URL, at now: Date) -> Bool {
        let path = url.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path) else { return false }
        try? FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: path)
        return true
    }

    /// Path separators and leading dots can't escape the folder or hide the file.
    public static func safeFilename(_ name: String) -> String {
        let cleaned = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: ". ").union(.whitespacesAndNewlines))
        return cleaned.isEmpty ? "Attachment" : cleaned
    }
}
