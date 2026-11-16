public import Foundation

extension PendingReply {
    /// The reply as the classic layout shows it until its copy syncs: a message made from the draft, with the
    /// words, quote and files it sends.
    public var letter: Message {
        Message(
            id: letterID, threadID: draft.threadID ?? "", from: sender, to: draft.to, cc: draft.cc, bcc: draft.bcc,
            subject: draft.subject, date: date, snippet: draft.body.plain ?? "",
            body: MessageBody(
                html: draft.body.html == nil ? nil : MIMEWriter.html(draft), plain: MIMEWriter.plainText(draft)),
            attachments: draft.attachments.map { file in
                Attachment(id: file.id.uuidString, filename: file.filename, mimeType: file.mimeType, size: file.size)
            },
            internetMessageID: headerID, references: draft.references)
    }

    /// The ID `letter` goes by. It names no message the provider has.
    public var letterID: Message.ID {
        Message.ID(accountID: draft.accountID, messageID: "pending-\(draft.id.uuidString)")
    }

    /// The bytes of one of the letter's files, which only the draft holds, or `nil` for a file still to be fetched
    /// from a forwarded message.
    public func data(for attachment: Attachment) -> Data? {
        draft.attachments.first { $0.id.uuidString == attachment.id }?.data
    }
}
