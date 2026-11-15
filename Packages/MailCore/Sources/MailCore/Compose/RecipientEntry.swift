import Foundation

/// One recipient field as the writer edits it: the people already turned into tokens, then either the text still
/// being typed after them or one selected token, which the next Delete removes whole.
public struct RecipientEntry: Equatable, Sendable {
    public private(set) var contacts: [Contact]
    public private(set) var focus: Focus

    public enum Focus: Equatable, Sendable {
        /// Typing after the tokens: what isn't a token yet.
        case typing(String)
        /// The token at this index is selected.
        case selected(Int)
    }

    public init(_ contacts: [Contact] = []) {
        self.contacts = []
        focus = .typing("")
        for contact in contacts { append(contact) }
    }

    /// What is typed after the tokens.
    public var typed: String {
        if case .typing(let text) = focus { text } else { "" }
    }

    public var selected: Int? {
        if case .selected(let index) = focus { index } else { nil }
    }

    /// Everyone the field holds, with whatever is typed read as recipients too.
    public var all: [Contact] { contacts + Contact.list(parsing: typed) }

    public var isEmpty: Bool { all.isEmpty }

    /// Takes the field's new text. Each recipient finished with a comma, a semicolon or a line break becomes a
    /// token, so typing or pasting a list tokenizes it; the text after the last one stays typed.
    public mutating func type(_ text: String) {
        let end = Self.endOfFinishedEntries(in: text)
        for contact in Contact.list(parsing: String(text[..<end]).replacing(/[;\n]/, with: ",")) { append(contact) }
        focus = .typing(String(text[end...].trimmingPrefix(while: \.isWhitespace)))
    }

    /// Turns what is typed into tokens, as leaving the field or Return does.
    public mutating func commit() {
        for contact in Contact.list(parsing: typed.replacing(/[;\n]/, with: ",")) { append(contact) }
        focus = .typing("")
    }

    /// Adds a picked suggestion in place of what is typed.
    public mutating func complete(with contact: Contact) {
        append(contact)
        focus = .typing("")
    }

    /// Delete with nothing typed selects the last token, and with a token selected removes it. Returns `false`
    /// when Delete should take a typed character instead.
    public mutating func deleteBackward() -> Bool {
        switch focus {
        case .selected(let index):
            remove(at: index)
            return true
        case .typing(let text) where text.isEmpty && !contacts.isEmpty:
            focus = .selected(contacts.count - 1)
            return true
        case .typing:
            return false
        }
    }

    /// Selects a token, keeping anything typed as tokens first.
    public mutating func select(_ index: Int) {
        guard contacts.indices.contains(index) else { return }
        commit()
        focus = .selected(index)
    }

    /// Goes back to typing after the tokens.
    public mutating func deselect() {
        if case .selected = focus { focus = .typing("") }
    }

    public mutating func remove(at index: Int) {
        guard contacts.indices.contains(index) else { return }
        contacts.remove(at: index)
        if case .selected = focus { focus = .typing("") }
    }

    /// Puts `contact` at `index`, or leaves the field as it is when it already holds that address.
    public mutating func insert(_ contact: Contact, at index: Int) {
        guard !contains(contact) else { return }
        contacts.insert(contact, at: min(max(index, 0), contacts.count))
        if case .selected = focus { focus = .typing("") }
    }

    private mutating func append(_ contact: Contact) {
        insert(contact, at: contacts.count)
    }

    private func contains(_ contact: Contact) -> Bool {
        contacts.contains { $0.address.caseInsensitiveCompare(contact.address) == .orderedSame }
    }

    /// Where the text after the last separator starts: after the last comma, semicolon or line break that isn't
    /// inside quotes or angle brackets.
    private static func endOfFinishedEntries(in text: String) -> String.Index {
        var context = AddressListContext.plain
        var end = text.startIndex
        for index in text.indices {
            if ",;\n".contains(text[index]), context == .plain { end = text.index(after: index) }
            context = context.after(text[index])
        }
        return end
    }
}

/// The three recipient fields of a message.
public struct Recipients: Equatable, Sendable {
    public enum Role: CaseIterable, Hashable, Sendable {
        case to, cc, bcc
    }

    public var to: RecipientEntry
    public var cc: RecipientEntry
    public var bcc: RecipientEntry

    public init(to: [Contact] = [], cc: [Contact] = [], bcc: [Contact] = []) {
        self.to = RecipientEntry(to)
        self.cc = RecipientEntry(cc)
        self.bcc = RecipientEntry(bcc)
    }

    public subscript(role: Role) -> RecipientEntry {
        get {
            switch role {
            case .to: to
            case .cc: cc
            case .bcc: bcc
            }
        }
        set {
            switch role {
            case .to: to = newValue
            case .cc: cc = newValue
            case .bcc: bcc = newValue
            }
        }
    }

    /// Everyone the message is addressed to, in every field.
    public var all: [Contact] { Role.allCases.flatMap { self[$0].all } }

    /// Moves a token to another field, or to another place in its own, as a drag does.
    public mutating func move(_ index: Int, from source: Role, to destination: Role, at target: Int) {
        guard self[source].contacts.indices.contains(index) else { return }
        let contact = self[source].contacts[index]
        self[source].remove(at: index)
        // Within one field the removal shifted every later place back by one.
        let target = source == destination && target > index ? target - 1 : target
        self[destination].insert(contact, at: target)
    }
}

extension Contact {
    /// Whether `text` reads as one email address: one `@` with a dotted domain, and no spaces.
    public static func isAddress(_ text: String) -> Bool {
        let parts = text.split(separator: "@", omittingEmptySubsequences: false)
        return parts.count == 2 && !parts[0].isEmpty && parts[1].contains(".") && !text.contains(" ")
            && !parts[1].hasPrefix(".") && !parts[1].hasSuffix(".")
    }

    /// Whether this contact's address can be sent to.
    public var hasValidAddress: Bool { Self.isAddress(address) }

    /// The contact as it is typed or pasted: `Name <a@b.c>`, quoted when the name has a comma, or the bare address.
    public var typedForm: String {
        guard let name, !name.isEmpty else { return address }
        return "\(name.contains(",") ? "\"\(name)\"" : name) <\(address)>"
    }
}
