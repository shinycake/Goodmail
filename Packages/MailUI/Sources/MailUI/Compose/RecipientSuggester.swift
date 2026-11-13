import MailCore

/// Whether the app may read the device's Contacts.
nonisolated public enum ContactsAccess: Equatable, Sendable {
    /// Nobody has been asked yet; the system asks the first time access is requested.
    case notDetermined
    /// Refused, or restricted by the device's owner. The app can't ask again; the user can in Settings.
    case denied
    /// The user shared only some contacts (iOS 18 and later). Only those can be read.
    case limited
    case authorized

    var canRead: Bool { self == .authorized || self == .limited }
}

/// The device's Contacts, as far as recipients are concerned.
nonisolated public protocol DeviceContacts: Sendable {
    var access: ContactsAccess { get async }
    /// Asks the user, when they haven't answered yet. Returns the access they left.
    func requestAccess() async -> ContactsAccess
    /// Every address in the book, once for each card it is on, with that card's name.
    func people() async throws -> [Contact]
}

/// Finds people to offer for a recipient being typed: those who wrote in and the Google address book first, then the
/// device's Contacts. Device Contacts are asked for the first time something is typed, never earlier, and read once for
/// the suggester's life, which is one compose sheet.
///
/// An actor, so the database lookup and the matching and sorting over the whole book stay off the main actor on every
/// keystroke.
public actor RecipientSuggester {
    private let writtenIn: @Sendable (String) throws -> [Contact]
    private let addressBook: any DeviceContacts
    /// The device's people, once they have been read, or none while access is withheld.
    private var device: [Contact]?

    /// `writtenIn` finds the people mail and Google Contacts know, best first. It reads the database, so it is called
    /// on this actor, never on the main actor.
    public init(writtenIn: @escaping @Sendable (String) throws -> [Contact], addressBook: any DeviceContacts) {
        self.writtenIn = writtenIn
        self.addressBook = addressBook
    }

    public func suggestions(for typed: String, limit: Int = 5) async -> [Contact] {
        let device = await devicePeople()
        // A database that fails to read costs only the suggestions from mail, not the device's.
        let known = (try? writtenIn(typed)) ?? []
        let matching = device.filter { Self.matches($0, typed) }.sorted {
            $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
        return Self.merged(known: known, device: device, matching: matching, limit: limit)
    }

    /// The device's people, read the first time they're needed. A book that fails to read costs only its own
    /// suggestions, not the ones from mail.
    private func devicePeople() async -> [Contact] {
        if let device { return device }
        var access = await addressBook.access
        if access == .notDetermined { access = await addressBook.requestAccess() }
        let people = access.canRead ? ((try? await addressBook.people()) ?? []) : []
        // Another keystroke may have read the book while this one waited; either read is the same book.
        if device == nil { device = people }
        return device ?? people
    }

    /// `known` in its order, then the `matching` device people it doesn't already hold. One address makes one
    /// suggestion, named as the device names it, as the owner's own cards beat the name on a message.
    static func merged(known: [Contact], device: [Contact], matching: [Contact], limit: Int) -> [Contact] {
        var names: [String: String] = [:]
        for person in device {
            guard let name = person.name, !name.isEmpty else { continue }
            names[person.address.lowercased()] = names[person.address.lowercased()] ?? name
        }
        var seen: Set<String> = []
        var result: [Contact] = []
        for person in known + matching where seen.insert(person.address.lowercased()).inserted {
            result.append(Contact(name: names[person.address.lowercased()] ?? person.name, address: person.address))
        }
        return Array(result.prefix(limit))
    }

    /// Whether the address or the name, or a word of it, starts with what was typed.
    static func matches(_ person: Contact, _ typed: String) -> Bool {
        let options: String.CompareOptions = [.anchored, .caseInsensitive, .diacriticInsensitive]
        let words = (person.name ?? "").split(separator: " ").map(String.init)
        return ([person.address, person.name ?? ""] + words).contains {
            $0.range(of: typed, options: options) != nil
        }
    }
}
