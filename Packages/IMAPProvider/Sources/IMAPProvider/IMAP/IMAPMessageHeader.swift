import Foundation
import MailCore

/// One `* n FETCH (...)` response's items, by upper-cased name.
struct IMAPFetch: Equatable, Sendable {
    var items: [String: IMAPValue]

    init?(response values: [IMAPValue]) {
        guard values.count == 3, values[1].atom?.uppercased() == "FETCH", let list = values[2].list,
            list.count.isMultiple(of: 2)
        else { return nil }
        var items: [String: IMAPValue] = [:]
        for index in stride(from: 0, to: list.count, by: 2) {
            guard let name = list[index].atom else { return nil }
            items[name.uppercased()] = list[index + 1]
        }
        self.items = items
    }

    /// The item whose name starts with `prefix`, for section items the server echoes in its own spelling.
    func item(prefixed prefix: String) -> IMAPValue? {
        items.first { $0.key.hasPrefix(prefix) }?.value
    }
}

/// One whole message, as `BODY.PEEK[]` returns it, with the flags and date IMAP keeps outside it.
struct IMAPMessageContent: Equatable, Sendable {
    var uid: UInt32
    var flags: Set<String>
    var receivedAt: Date
    /// The RFC 5322 message.
    var raw: Data

    init?(fetch: IMAPFetch) {
        guard let uid = fetch.items["UID"]?.number, let raw = fetch.items["BODY[]"]?.bytes,
            let received = fetch.items["INTERNALDATE"]?.bytes.flatMap(IMAPMessageHeader.internalDate)
        else { return nil }
        self.uid = uid
        flags = Set(fetch.items["FLAGS"]?.list?.compactMap(\.atom) ?? [])
        receivedAt = received
        self.raw = raw
    }
}

/// What the mailbox list and threading need from one message, fetched without its body.
struct IMAPMessageHeader: Equatable, Sendable {
    var uid: UInt32
    var flags: Set<String>
    /// When the server received it, which orders the mailbox.
    var receivedAt: Date
    var subject: String
    var from: [Contact]
    var to: [Contact]
    var cc: [Contact]
    /// `id@host`, without its angle brackets.
    var messageID: String?
    var inReplyTo: String?
    /// The message IDs it answers, oldest first.
    var references: [String]
    /// The start of its text, as the mailbox list shows it.
    var snippet: String

    var isUnread: Bool { !flags.contains(#"\Seen"#) }

    init?(fetch: IMAPFetch) {
        guard let uid = fetch.items["UID"]?.number,
            let envelope = fetch.items["ENVELOPE"]?.list, envelope.count == 10,
            let received = fetch.items["INTERNALDATE"]?.bytes.flatMap(Self.internalDate)
        else { return nil }
        self.uid = uid
        flags = Set(fetch.items["FLAGS"]?.list?.compactMap(\.atom) ?? [])
        receivedAt = received
        subject = Self.text(envelope[1]) ?? ""
        from = Self.addresses(envelope[2])
        to = Self.addresses(envelope[5])
        cc = Self.addresses(envelope[6])
        inReplyTo = Self.text(envelope[8]).flatMap { Message.messageIDs(in: $0).first }
        messageID = Self.text(envelope[9]).flatMap { Message.messageIDs(in: $0).first }
        let fields = fetch.item(prefixed: "BODY[HEADER.FIELDS").flatMap(\.bytes) ?? Data()
        references = Message.messageIDs(in: String(decoding: fields, as: UTF8.self))
        // The start of the text under the headers that say how to read it parses like a message cut short.
        let text = fetch.item(prefixed: "BODY[TEXT]").flatMap(\.bytes)
        snippet = text.map { MIMEPart(parsing: fields + $0).content().body.snippet } ?? ""
    }

    private static func text(_ value: IMAPValue) -> String? {
        value.bytes.map { EncodedWords.decode(TextDecoding.string(from: $0, declaredCharset: nil)) }
    }

    /// An envelope address list: `(("Name" NIL "mailbox" "host") ...)`. Group syntax markers are skipped.
    private static func addresses(_ value: IMAPValue) -> [Contact] {
        (value.list ?? []).compactMap { address in
            guard let parts = address.list, parts.count == 4, let mailbox = text(parts[2]), let host = text(parts[3])
            else { return nil }
            let name = text(parts[0]).flatMap { $0.isEmpty ? nil : $0 }
            return Contact(name: name, address: "\(mailbox)@\(host)")
        }
    }

    /// `17-Jul-1996 02:44:25 -0700`, with the day sometimes padded by a space.
    static func internalDate(_ bytes: Data) -> Date? {
        let text = String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespaces)
        return try? Date(text, strategy: internalDateFormat)
    }

    private static let internalDateFormat = Date.VerbatimFormatStyle(
        format:
            "\(day: .defaultDigits)-\(month: .abbreviated)-\(year: .defaultDigits) \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits):\(second: .twoDigits) \(timeZone: .iso8601(.short))",
        locale: Locale(identifier: "en_US_POSIX"),
        timeZone: .gmt,
        calendar: Calendar(identifier: .gregorian)
    ).parseStrategy
}
