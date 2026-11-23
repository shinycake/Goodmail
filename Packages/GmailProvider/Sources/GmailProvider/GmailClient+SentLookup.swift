import Foundation
public import MailCore

/// Whether a send whose answer never came went anyway. Gmail's API sends under a `Message-ID` of its own, so the
/// message is looked for by the one Goodmail wrote and by the copy of it in `MIMEWriter.sentIDHeader`.
extension GmailClient {
    /// How much earlier than its time a sent message may be dated, as Gmail's clock and the device's differ.
    static let sentClockSkew: TimeInterval = 15 * 60
    /// The most sent messages looked through for a lost send: those to its recipient since its time, oldest first.
    static let sentLookback = 500
    /// How many of them are read at once, as the rest of the client fetches a few at a time.
    static let sentBatch = 10

    public func hasSent(_ message: OutgoingMessage) async throws -> Bool {
        if try await !sentMessages(matching: "rfc822msgid:\(message.headerID)", limit: 1).isEmpty { return true }
        let candidates = try await sentMessages(matching: Self.lookbackQuery(for: message), limit: Self.sentLookback)
        // Listed newest first; the lost send went at about its time, so it is among the oldest.
        var failure: (any Error)?
        for batch in Self.batches(of: candidates.reversed()) {
            switch try await carrier(of: message.headerID, among: batch) {
            case .found: return true
            case .absent: continue
            case .unread(let error): failure = failure ?? error
            }
        }
        // A message that couldn't be read may be the one, so whether it went stays unknown, to ask again.
        if let failure { throw failure }
        return false
    }

    /// Sent mail since the message's time, give or take the clocks, to the first person it went to.
    static func lookbackQuery(for message: OutgoingMessage) -> String {
        let since = Int(message.sendAt.addingTimeInterval(-sentClockSkew).timeIntervalSince1970)
        let draft = message.draft
        guard let address = (draft.to + draft.cc + draft.bcc).first?.address else { return "after:\(since)" }
        return "after:\(since) {to:\(address) cc:\(address) bcc:\(address)}"
    }

    private static func batches(of ids: [String]) -> [[String]] {
        stride(from: 0, to: ids.count, by: sentBatch).map { Array(ids[$0..<min($0 + sentBatch, ids.count)]) }
    }

    /// The IDs of the sent messages `query` finds, newest first, up to `limit`, never a draft carrying the same
    /// headers.
    private func sentMessages(matching query: String, limit: Int) async throws -> [String] {
        var ids: [String] = []
        var pageToken: String?
        repeat {
            var items = [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "labelIds", value: SystemLabel.sent),
                URLQueryItem(name: "includeSpamTrash", value: "true"),
                URLQueryItem(name: "maxResults", value: String(min(limit - ids.count, 100))),
            ]
            if let pageToken { items.append(URLQueryItem(name: "pageToken", value: pageToken)) }
            let list: GmailMessageList = try await get("users/me/messages", query: items)
            ids += (list.messages ?? []).map(\.id)
            pageToken = list.nextPageToken
        } while pageToken != nil && ids.count < limit
        return ids
    }

    /// What reading a batch of sent messages for the lost send's header found.
    private enum Lookup: Sendable {
        case found
        case absent
        /// None carries it, but at least one couldn't be read.
        case unread(any Error)
    }

    /// Reads the batch at once for `headerID` in `MIMEWriter.sentIDHeader`. A message deleted meanwhile doesn't carry
    /// it; one that fails to read for now leaves the answer open unless another carries it.
    private func carrier(of headerID: String, among ids: [String]) async throws -> Lookup {
        try await withThrowingTaskGroup(of: Lookup.self) { group in
            for id in ids {
                group.addTask {
                    do {
                        let message: GmailThread.Message = try await get(
                            "users/me/messages/\(id)",
                            query: [
                                URLQueryItem(name: "format", value: "metadata"),
                                URLQueryItem(name: "metadataHeaders", value: MIMEWriter.sentIDHeader),
                            ])
                        let ids = message.header(MIMEWriter.sentIDHeader).map(Message.messageIDs(in:)) ?? []
                        return ids.contains(headerID) ? .found : .absent
                    } catch let error as GmailError where [400, 404].contains(error.status) {
                        // Deleted meanwhile, or one Gmail won't read the same way however often it's asked.
                        return .absent
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        return .unread(error)
                    }
                }
            }
            var unread: (any Error)?
            for try await lookup in group {
                switch lookup {
                case .found:
                    group.cancelAll()
                    return .found
                case .absent: continue
                case .unread(let error): unread = unread ?? error
                }
            }
            return unread.map(Lookup.unread) ?? .absent
        }
    }
}
