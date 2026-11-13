import Foundation
import MailCore

extension ICloudClient {
    /// Sends over SMTP, then files the message in Sent, unless iCloud already did. Filing never fails a send: the
    /// outbox would send the message again, and the next `changes(since:)` finds a copy iCloud filed late.
    public func send(_ raw: Data, inThread threadID: String?) async throws {
        guard let envelope = SMTPEnvelope(raw) else { throw ProviderError.rejected }
        do {
            try await smtp.send(envelope)
        } catch SMTPError.refused(let reply) where reply.isPermanentFailure {
            throw ProviderError.rejected
        }
        try? await file(raw, as: SystemLabel.sent, flags: [#"\Seen"#], inThread: threadID, unlessFiled: true)
    }

    /// Files the draft in Drafts, then removes the one it replaces.
    public func saveDraft(_ raw: Data, inThread threadID: String?, replacing: Message.ID?) async throws {
        try await file(
            raw, as: SystemLabel.draft, flags: [#"\Seen"#, #"\Draft"#], inThread: threadID, unlessFiled: false)
        if let replacing { try await deleteDraft(replacing) }
    }

    public func deleteDraft(_ message: Message.ID) async throws {
        guard let key = MessageKey(rawValue: message.messageID) else { return }
        try await session.run { connection in
            guard Folders(try await connection.mailboxes()).contains(key.folder),
                try await connection.select(key.folder).uidValidity == key.uidValidity
            else { return }
            try await connection.expunge([key.uid])
            try index.forgetIndexEntries(withKeys: [key.rawValue], account: accountID)
        }
    }

    /// APPENDs `raw` to the folder of `label` and indexes it in its thread: `threadID`, or the one its headers give.
    /// With `unlessFiled`, a message the folder already holds, by its Message-ID, isn't filed again.
    private func file(
        _ raw: Data, as label: String, flags: Set<String>, inThread threadID: String?, unlessFiled: Bool
    ) async throws {
        let headers = MIMEPart(parsing: raw)
        let messageID = headers.header("Message-ID").flatMap { IMAPMessageHeader.messageIDs(in: $0).first }
        let references = IMAPMessageHeader.messageIDs(in: headers.header("References") ?? "")
        try await session.run { connection in
            guard let folder = Folders(try await connection.mailboxes()).folder(for: label) else { return }
            if unlessFiled, let messageID {
                try await connection.select(folder.wireName)
                guard try await connection.searchUIDs(IMAPSearch(messageID: messageID)).isEmpty else { return }
            }
            guard let landed = try await connection.append(raw, to: folder.wireName, flags: flags) else { return }
            let key = MessageKey(folder: folder.wireName, uidValidity: landed.uidValidity, uid: landed.uid)
            let thread = threadID ?? references.first ?? messageID ?? key.rawValue
            try index.record(
                [MessageIndexEntry(key: key.rawValue, threadID: thread, internetMessageID: messageID)],
                account: accountID)
        }
    }
}
