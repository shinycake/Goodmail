import Foundation
import MailCore

#if canImport(FoundationNetworking)
    import FoundationNetworking  // URLSession on Linux
#endif

/// A conversation's messages, read as the RFC 5322 messages Exchange keeps (`$value`) and parsed the way every
/// provider's MIME is, so Outlook mail reads exactly as Gmail and iCloud mail does.
extension OutlookClient {
    public func messages(inThread threadID: String) async throws -> [Message] {
        let directory = try await folderDirectory()
        let listed: [GraphMessage] = try await conversation(threadID, select: GraphMessage.summaryFields)
        guard !listed.isEmpty else { throw ProviderError.notFound }
        let accountID = graph.session.accountID
        var messages: [Message] = []
        try await withThrowingTaskGroup(of: Message?.self) { group in
            for listing in listed {
                group.addTask {
                    // A message deleted since the listing is simply left out.
                    guard let mime = try await mime(of: listing.id) else { return nil }
                    return Message(
                        id: Message.ID(accountID: accountID, messageID: listing.id),
                        threadID: threadID,
                        mime: mime,
                        date: listing.receivedDateTime ?? .distantPast,
                        snippet: listing.bodyPreview ?? "",
                        labelIDs: listing.labelIDs(in: directory))
                }
            }
            for try await message in group { message.map { messages.append($0) } }
        }
        return messages.sorted { $0.date < $1.date }
    }

    /// Graph's attachment IDs aren't MIME part IDs, so the attachment comes from the message's MIME again.
    public func data(for attachment: Attachment, in message: Message.ID) async throws -> Data {
        guard let data = try await mime(of: message.messageID)?.part(withID: attachment.id)?.data else {
            throw ProviderError.notFound
        }
        return data
    }

    /// The message's MIME, or `nil` when it's gone.
    private func mime(of messageID: String) async throws -> MIMEPart? {
        let url = GraphTransport.baseURL.appending(path: "me/messages/\(messageID)/$value")
        do {
            return MIMEPart(parsing: try await graph.send(url, method: "GET", payload: nil))
        } catch let error as GraphError where error.status == 404 {
            return nil
        }
    }
}
