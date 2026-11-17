public import AppIntents
public import CoreTransferable
import Foundation
import MailCore

/// Someone mail comes from, known by address. Messages and conversations name theirs as From, Find compares it, and
/// the picker offers the people who write most, so "everything from Dana older than a week" takes a person, not a
/// typed address.
public struct SenderEntity: AppEntity, Sendable {
    public static let typeDisplayRepresentation: TypeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("Sender", table: "ShortcutFlow"))
    public static let defaultQuery = SenderQuery()

    /// The address in lowercase, since mail treats addresses alike whatever their case.
    public let id: String
    @Property(title: LocalizedStringResource("Name", table: "ShortcutFlow"))
    public var name: String
    @Property(title: LocalizedStringResource("Address", table: "ShortcutFlow"))
    public var address: String
    /// The part of the address after `@`, as `amazon.com`.
    @Property(title: LocalizedStringResource("Domain", table: "ShortcutFlow"))
    public var domain: String

    public var displayRepresentation: DisplayRepresentation {
        name.isEmpty
            ? DisplayRepresentation(title: "\(address)")
            : DisplayRepresentation(title: "\(name)", subtitle: "\(address)")
    }

    init(_ contact: Contact) {
        id = contact.address.lowercased()
        name = contact.name ?? ""
        address = contact.address
        domain = contact.address.split(separator: "@").last.map { $0.lowercased() } ?? ""
    }

    /// The sender as a recipient is typed, `Name <address>`, for a To field or a note.
    var typed: String { Contact(name: name.isEmpty ? nil : name, address: address).typedForm }
}

/// Two senders are the same person when their addresses match, whatever names the mail gave them, which is what
/// Find's From is and isn't compares.
extension SenderEntity: Equatable {
    public static func == (lhs: SenderEntity, rhs: SenderEntity) -> Bool { lhs.id == rhs.id }
}

/// A sender reads as `Name <address>` wherever a shortcut wants text.
extension SenderEntity: Transferable {
    public static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(exporting: \.typed)
    }
}

/// Offers the people who wrote most to the Inbox lately, finds them by name or address, and takes any address typed
/// in, so a sender who hasn't written in a while can still be chosen.
public struct SenderQuery: EntityStringQuery {
    @Dependency private var host: any MailIntentsHost

    public init() {}

    public func entities(for identifiers: [String]) async throws -> [SenderEntity] {
        try Catalog(host: host).senders(identifiers)
    }

    public func entities(matching string: String) async throws -> [SenderEntity] {
        try Catalog(host: host).senders(matching: string)
    }

    public func suggestedEntities() async throws -> [SenderEntity] {
        try Array(Catalog(host: host).frequentSenders().prefix(Catalog.suggestionLimit))
    }
}

extension Catalog {
    /// How many of the newest Inbox conversations the sender picker reads.
    static let senderWindow = 500

    /// Who wrote the newest Inbox conversations, most conversations first, then the most recent. Leaves out the
    /// accounts' own addresses.
    func frequentSenders() throws -> [SenderEntity] {
        let own = Set(
            try host.accounts().flatMap { [$0.email] + $0.aliases.map(\.address) }.map { $0.lowercased() })
        var tally: [String: (contact: Contact, count: Int, newest: Int)] = [:]
        for (position, thread) in try host.threads(in: .inbox, limit: Self.senderWindow).enumerated() {
            let key = thread.sender.address.lowercased()
            guard !key.isEmpty, !own.contains(key) else { continue }
            if let seen = tally[key] {
                // Keep the name the newest conversation gives, unless it gave none.
                let contact = seen.contact.name == nil ? thread.sender : seen.contact
                tally[key] = (contact, seen.count + 1, seen.newest)
            } else {
                tally[key] = (thread.sender, 1, position)
            }
        }
        return tally.values
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.newest < $1.newest }
            .map { SenderEntity($0.contact) }
    }

    /// The senders with these identifiers, named as the Inbox names them, or by address alone when it doesn't.
    func senders(_ identifiers: [String]) throws -> [SenderEntity] {
        let known = Dictionary(try frequentSenders().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return identifiers.map { known[$0.lowercased()] ?? SenderEntity(Contact(name: nil, address: $0)) }
    }

    /// The senders whose name or address holds `text`. Typed text that reads as an address comes first, so any
    /// address can be chosen.
    func senders(matching text: String) throws -> [SenderEntity] {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let found = try frequentSenders().filter {
            $0.name.localizedStandardContains(text) || $0.address.localizedStandardContains(text)
        }
        let typed = Contact(parsing: text)
        guard Self.looksLikeAddress(typed.address), !found.contains(where: { $0.id == typed.address.lowercased() })
        else { return found }
        return [SenderEntity(typed)] + found
    }

    /// Something, an `@`, then a domain with a dot in it, without spaces.
    static func looksLikeAddress(_ text: String) -> Bool {
        let parts = text.split(separator: "@", omittingEmptySubsequences: false)
        return parts.count == 2 && !parts[0].isEmpty && parts[1].contains(".") && !parts[1].hasSuffix(".")
            && !text.contains(where: \.isWhitespace)
    }
}
