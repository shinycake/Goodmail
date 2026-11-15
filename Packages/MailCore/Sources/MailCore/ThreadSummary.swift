import Foundation

/// A conversation as the mailbox list shows it: who wrote last, about what, and when.
public struct ThreadSummary: Identifiable, Equatable, Sendable {
    public struct ID: Hashable, Codable, Sendable {
        public let accountID: AccountID
        /// The provider's thread identifier, unique only within its account.
        public let threadID: String

        public init(accountID: AccountID, threadID: String) {
            self.accountID = accountID
            self.threadID = threadID
        }
    }

    public let id: ID
    public var subject: String
    public var snippet: String
    /// The latest message's sender.
    public var sender: Contact
    /// The latest message's date.
    public var date: Date
    public var isUnread: Bool
    public var messageCount: Int
    /// Provider label or folder identifiers, such as Gmail's `INBOX` or `CATEGORY_SOCIAL`.
    public var labelIDs: Set<String>

    public init(
        id: ID,
        subject: String,
        snippet: String,
        sender: Contact,
        date: Date,
        isUnread: Bool,
        messageCount: Int,
        labelIDs: Set<String>
    ) {
        self.id = id
        self.subject = subject
        self.snippet = snippet
        self.sender = sender
        self.date = date
        self.isUnread = isUnread
        self.messageCount = messageCount
        self.labelIDs = labelIDs
    }
}

public struct Contact: Equatable, Hashable, Codable, Sendable {
    public var name: String?
    public var address: String

    public init(name: String?, address: String) {
        self.name = name
        self.address = address
    }

    /// The name when there is one, otherwise the address.
    public var displayName: String {
        guard let name, !name.isEmpty else { return address }
        return name
    }
}

extension Contact {
    /// Parses an RFC 5322 mailbox as providers return it, already MIME-decoded: `"Name" <a@b.c>`, `Name <a@b.c>` or
    /// `a@b.c`.
    public init(parsing header: String) {
        let trimmed = header.trimmingCharacters(in: .whitespaces)
        guard let open = trimmed.lastIndex(of: "<"), let close = trimmed.lastIndex(of: ">"), open < close else {
            self.init(name: nil, address: trimmed)
            return
        }
        let address = String(trimmed[trimmed.index(after: open)..<close])
        let name = trimmed[..<open]
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        self.init(name: name.isEmpty ? nil : name, address: address)
    }

    /// Parses an address list such as `To:`. Commas inside quotes or angle brackets don't split it.
    public static func list(parsing header: String) -> [Contact] {
        var mailboxes: [Substring] = []
        var start = header.startIndex
        for separator in separators(in: header) {
            mailboxes.append(header[start..<separator])
            start = header.index(after: separator)
        }
        mailboxes.append(header[start...])
        return mailboxes.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.map(
            Contact.init(parsing:))
    }

    /// The commas that separate the addresses of a list such as `To:`, in order. Commas inside quotes or angle
    /// brackets are part of an address.
    public static func separators(in list: String) -> [String.Index] {
        var context = AddressListContext.plain
        var separators: [String.Index] = []
        for index in list.indices {
            if list[index] == ",", context == .plain { separators.append(index) }
            context = context.after(list[index])
        }
        return separators
    }
}
