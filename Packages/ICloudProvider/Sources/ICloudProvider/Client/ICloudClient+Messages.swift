import Foundation
import MailCore

extension ICloudClient {
    /// The thread's messages, whole, from every folder the index has them in. A message filed in two folders is read
    /// once, with both folders' labels.
    public func messages(inThread threadID: String) async throws -> [Message] {
        try await session.run { connection in
            let folders = Folders(try await connection.mailboxes())
            let keys = try index.indexEntries(inThreads: [threadID], account: accountID).compactMap {
                MessageKey(rawValue: $0.key)
            }
            var messages: [Message] = []
            for (folder, keys) in Dictionary(grouping: keys, by: \.folder).sorted(by: { $0.key < $1.key })
            where folders.contains(folder) {
                let selection = try await connection.select(folder)
                let uids = keys.filter { $0.uidValidity == selection.uidValidity }.map(\.uid)
                let label = folders.label(ofFolderNamed: folder)
                messages += try await connection.messages(uids).map { content in
                    let key = MessageKey(folder: folder, uidValidity: selection.uidValidity, uid: content.uid)
                    var message = Message(
                        id: Message.ID(accountID: accountID, messageID: key.rawValue), threadID: threadID,
                        mime: MIMEPart(parsing: content.raw), date: content.receivedAt, snippet: "",
                        labelIDs: Folders.labelIDs(folderLabel: label, flags: content.flags))
                    // IMAP keeps no snippet, so it comes from the body the message was just read with.
                    message.snippet = message.body.snippet
                    return message
                }
            }
            guard !messages.isEmpty else { throw ProviderError.notFound }
            return Self.distinct(messages).sorted { $0.date < $1.date }
        }
    }

    /// Reads the message again and takes the part out, since IMAP part IDs are its section numbers.
    public func data(for attachment: Attachment, in message: Message.ID) async throws -> Data {
        guard let key = MessageKey(rawValue: message.messageID) else { throw ProviderError.notFound }
        return try await session.run { connection in
            guard Folders(try await connection.mailboxes()).contains(key.folder),
                try await connection.select(key.folder).uidValidity == key.uidValidity,
                let content = try await connection.messages([key.uid]).first,
                let data = MIMEPart(parsing: content.raw).part(withID: attachment.id)?.data
            else { throw ProviderError.notFound }
            return data
        }
    }

    /// One message per Message-ID, with the labels of every copy.
    private static func distinct(_ messages: [Message]) -> [Message] {
        var byID: [String: Message] = [:]
        var order: [String] = []
        for message in messages {
            let id = message.internetMessageID ?? message.id.messageID
            if byID[id] == nil { order.append(id) }
            byID[id, default: message].labelIDs.formUnion(message.labelIDs)
        }
        return order.compactMap { byID[$0] }
    }
}
