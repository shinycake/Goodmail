public import Foundation

/// What another app shared into a new message through the Share extension: a title, text, links and files, in the
/// order they came.
public struct SharedContent: Equatable, Sendable {
    /// The shared page's or item's own title, as Safari gives a page's.
    public var title: String?
    public var texts: [String]
    public var links: [URL]
    public var files: [DraftAttachment]

    public init(title: String? = nil, texts: [String] = [], links: [URL] = [], files: [DraftAttachment] = []) {
        self.title = title
        self.texts = texts
        self.links = links
        self.files = files
    }

    /// The subject the message starts with: the title, when there is one.
    public var subject: String {
        title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// What the message says before anyone writes: each text, then each link the texts don't already hold, a
    /// paragraph each. Apps often share a link both as a link and inside their text, so a link shows once.
    public var body: String {
        let texts = texts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        var links: [String] = []
        for link in self.links.map(\.absoluteString)
        where !links.contains(link) && !texts.contains(where: { $0.contains(link) }) {
            links.append(link)
        }
        return (texts + links).joined(separator: "\n\n")
    }

    /// Nothing came that a message could carry.
    public var isEmpty: Bool { subject.isEmpty && body.isEmpty && files.isEmpty }
}
