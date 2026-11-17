public import Foundation
public import MailCore

/// A conversation as the iPhone sends it to the watch: its newest bubbles, as the iPhone's chat view reads them, small
/// enough for a WatchConnectivity message.
public struct WristThread: Codable, Equatable, Identifiable, Sendable {
    /// As many bubbles as the watch shows; earlier ones are counted, not sent.
    static let bubbleLimit = 12
    /// Words longer than this are cut, and the rest reads on the iPhone.
    static let wordsLimit = 600

    public var id: ThreadSummary.ID
    public var subject: String
    /// Oldest first.
    public var bubbles: [WristBubble]
    /// How many bubbles came before `bubbles`.
    public var earlier: Int
    /// Whether more than one other person takes part, so bubbles name their sender.
    public var isGroup: Bool
    /// A one-time code in the newest bubble from someone else, or the subject.
    public var code: String?

    public init(
        id: ThreadSummary.ID, subject: String, bubbles: [WristBubble], earlier: Int, isGroup: Bool, code: String?
    ) {
        self.id = id
        self.subject = subject
        self.bubbles = bubbles
        self.earlier = earlier
        self.isGroup = isGroup
        self.code = code
    }

    public init(id: ThreadSummary.ID, subject: String, transcript: ChatTranscript) {
        var all: [WristBubble] = []
        var time: Date?
        for entry in transcript.entries {
            switch entry {
            case .timestamp(let date):
                time = date
            case .run(let run):
                for bubble in run.bubbles {
                    all.append(
                        WristBubble(
                            side: run.side == .mine ? .mine : .theirs, sender: run.sender.displayName, time: time,
                            content: WristBubble.Content(bubble.content)))
                    time = nil
                }
            }
        }
        let shown = all.suffix(Self.bubbleLimit)
        let newestTheirs = shown.last { $0.side == .theirs }?.content.text ?? ""
        self.init(
            id: id, subject: subject, bubbles: Array(shown), earlier: all.count - shown.count,
            isGroup: transcript.isGroup, code: OneTimeCode(in: subject + "\n" + newestTheirs)?.code)
    }
}

public struct WristBubble: Codable, Equatable, Sendable {
    public enum Side: Codable, Equatable, Sendable {
        case mine
        case theirs
    }

    public enum Content: Codable, Equatable, Sendable {
        case words(String)
        /// A message that reads in full on the iPhone: long, laid out, or forwarded.
        case letter(subject: String, preview: String)
        case attachment(name: String)

        init(_ content: ChatTranscript.Content) {
            switch content {
            case .words(let segments, _):
                let words = segments.compactMap { segment -> String? in
                    if case .text(let text) = segment { text } else { nil }
                }
                self = .words(String(words.joined(separator: "\n").prefix(WristThread.wordsLimit)))
            case .letter(let subject, let preview):
                self = .letter(subject: subject, preview: String(preview.prefix(WristThread.wordsLimit)))
            case .attachment(let attachment):
                self = .attachment(name: attachment.filename)
            }
        }

        /// The words a reader sees, for finding a code.
        var text: String {
            switch self {
            case .words(let words): words
            case .letter(let subject, let preview): subject + "\n" + preview
            case .attachment(let name): name
            }
        }
    }

    public var side: Side
    /// Who wrote it, as the conversation names them.
    public var sender: String
    /// The time the conversation shows above this bubble, at its start and after each pause.
    public var time: Date?
    public var content: Content

    public init(side: Side, sender: String, time: Date?, content: Content) {
        self.side = side
        self.sender = sender
        self.time = time
        self.content = content
    }
}

/// The iPhone's answer to a request for a conversation.
public enum WristThreadReply: Codable, Equatable, Sendable {
    case thread(WristThread)
    /// The iPhone no longer has it, as after it was deleted.
    case gone(ThreadSummary.ID)

    public var id: ThreadSummary.ID {
        switch self {
        case .thread(let thread): thread.id
        case .gone(let id): id
        }
    }
}
