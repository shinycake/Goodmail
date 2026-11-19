public import Foundation
import MailCore

extension WristThreadReply {
    /// The reply as it crosses from the iPhone to the watch, in at most `limit` bytes when it can be. A conversation
    /// too big keeps its newest messages whole longest: the oldest letters are cut short first, then the oldest
    /// bubbles are left out and counted as earlier ones. One bubble that still doesn't fit goes as it is, and
    /// WatchConnectivity refuses it, which the watch reads as no answer.
    public func encoded(within limit: Int) throws -> Data {
        var reply = self
        var data = try JSONEncoder().encode(reply)
        while data.count > limit, case .thread(let thread) = reply, let smaller = thread.smaller(by: data.count - limit)
        {
            reply = .thread(smaller)
            data = try JSONEncoder().encode(reply)
        }
        return data
    }
}

extension WristThread {
    /// How short a letter is cut before bubbles are left out instead.
    static let shortestCut = 280

    /// One step smaller, aiming to save `excess` bytes: the oldest letter longer than `shortestCut` cut by that many
    /// bytes of its words, or else the oldest bubble left out. `nil` when neither can be done: no letter left to cut
    /// and only one bubble.
    func smaller(by excess: Int) -> WristThread? {
        var thread = self
        for index in bubbles.indices {
            guard case .letter(let letter) = bubbles[index].content, letter.words.plain.count > Self.shortestCut else {
                continue
            }
            let bytes = letter.words.plain.utf8.count - excess
            thread.bubbles[index].content = .letter(letter.cut(toBytes: bytes, minimum: Self.shortestCut))
            return thread
        }
        guard bubbles.count > 1 else { return nil }
        thread.bubbles.removeFirst()
        thread.earlier += 1
        return thread
    }
}
