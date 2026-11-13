import Foundation
import MailCore

#if canImport(FoundationNetworking)
    import FoundationNetworking  // URLSession on Linux
#endif

/// Sending, drafts and the address book. Graph takes a whole RFC 5322 message as base64 text, so the composed MIME
/// goes out as it is, headers and all.
extension OutlookClient {
    /// The largest message Graph takes as MIME: a request is capped at 4 MB, and base64 grows the message by a third.
    static let mimeLimit = 3_000_000

    /// Sends `raw`. Exchange files it in the conversation its `In-Reply-To` and `References` headers name, so the
    /// thread needs no ID of its own here.
    public func send(_ raw: Data, inThread threadID: String?) async throws {
        try await postMIME(raw, to: "me/sendMail")
    }

    /// Saves `raw` as a new draft, then deletes the one it replaces. Graph can't rewrite a draft from MIME, and
    /// creating first means a failure never loses the user's draft.
    public func saveDraft(_ raw: Data, inThread threadID: String?, replacing: Message.ID?) async throws {
        try await postMIME(raw, to: "me/messages")
        if let replacing { try await deleteDraft(replacing) }
    }

    /// Deletes the draft for good, as Gmail does, rather than moving it to Deleted Items. One already gone is fine.
    public func deleteDraft(_ message: Message.ID) async throws {
        let url = GraphTransport.baseURL.appending(path: "me/messages/\(message.messageID)/permanentDelete")
        do {
            try await graph.send(url, method: "POST", payload: nil)
        } catch let error as GraphError where error.status == 404 {
            return
        }
    }

    /// The saved contacts, then the people the account writes to most, each address once.
    public func contacts() async throws -> [Contact] {
        var saved: [GraphContact] = []
        var next: URL? = GraphTransport.baseURL.appending(path: "me/contacts").appending(queryItems: [
            URLQueryItem(name: "$select", value: "displayName,emailAddresses"),
            URLQueryItem(name: "$top", value: "1000"),
        ])
        while let url = next {
            let page: GraphPage<GraphContact> = try await graph.get(url)
            saved += page.value
            next = page.nextLink
        }
        // People ranks by how much the account writes to them; its first page is the part worth suggesting.
        let people: GraphPage<GraphPerson> = try await graph.get(
            "me/people",
            query: [
                URLQueryItem(name: "$select", value: "displayName,scoredEmailAddresses"),
                URLQueryItem(name: "$top", value: "1000"),
            ])
        var seen: Set<String> = []
        return (saved.flatMap(\.contacts) + people.value.flatMap(\.contacts)).filter {
            seen.insert($0.address.lowercased()).inserted
        }
    }

    /// Graph doesn't expose Outlook's signatures, so the app's own stands alone.
    public func signature() async throws -> String {
        ""
    }

    private func postMIME(_ raw: Data, to path: String) async throws {
        guard raw.count <= Self.mimeLimit else { throw ProviderError.rejected }
        do {
            try await graph.send(
                GraphTransport.baseURL.appending(path: path), method: "POST",
                payload: (raw.base64EncodedData(), "text/plain"))
        } catch let error as GraphError where error.status == 400 {
            throw ProviderError.rejected
        }
    }
}
