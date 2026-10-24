import Foundation

/// One message as the reader shows it: its people, its body and its attachments.
public struct Message: Identifiable, Equatable, Codable, Sendable {
    public struct ID: Hashable, Codable, Sendable {
        public let accountID: AccountID
        /// The provider's message identifier, unique only within its account.
        public let messageID: String

        public init(accountID: AccountID, messageID: String) {
            self.accountID = accountID
            self.messageID = messageID
        }
    }

    public let id: ID
    public var threadID: String
    public var from: Contact
    public var to: [Contact]
    public var cc: [Contact]
    public var replyTo: [Contact]
    public var subject: String
    public var date: Date
    public var snippet: String
    public var labelIDs: Set<String>
    public var body: MessageBody
    public var attachments: [Attachment]
    /// The RFC 5322 `Message-ID` and `References`, which replies thread on.
    public var internetMessageID: String?
    public var references: [String]

    public var isUnread: Bool { labelIDs.contains("UNREAD") }

    public init(
        id: ID,
        threadID: String,
        from: Contact,
        to: [Contact] = [],
        cc: [Contact] = [],
        replyTo: [Contact] = [],
        subject: String,
        date: Date,
        snippet: String = "",
        labelIDs: Set<String> = [],
        body: MessageBody,
        attachments: [Attachment] = [],
        internetMessageID: String? = nil,
        references: [String] = []
    ) {
        self.id = id
        self.threadID = threadID
        self.from = from
        self.to = to
        self.cc = cc
        self.replyTo = replyTo
        self.subject = subject
        self.date = date
        self.snippet = snippet
        self.labelIDs = labelIDs
        self.body = body
        self.attachments = attachments
        self.internetMessageID = internetMessageID
        self.references = references
    }
}

public struct MessageBody: Hashable, Codable, Sendable {
    public var html: String?
    public var plain: String?

    public init(html: String? = nil, plain: String? = nil) {
        self.html = html
        self.plain = plain
    }
}

/// A file carried by a message. Inline ones are images the HTML body shows through `cid:` URLs.
public struct Attachment: Identifiable, Equatable, Codable, Sendable {
    /// The MIME part ID, stable for the life of the message.
    public let id: String
    public var filename: String
    public var mimeType: String
    public var size: Int
    /// The `Content-ID` without angle brackets, which `cid:` URLs name.
    public var contentID: String?
    public var isInline: Bool
    /// What the provider needs to fetch the data, such as Gmail's attachment ID.
    public var fetchToken: String?

    public init(
        id: String,
        filename: String,
        mimeType: String,
        size: Int,
        contentID: String? = nil,
        isInline: Bool = false,
        fetchToken: String? = nil
    ) {
        self.id = id
        self.filename = filename
        self.mimeType = mimeType
        self.size = size
        self.contentID = contentID
        self.isInline = isInline
        self.fetchToken = fetchToken
    }
}
