public import Foundation
public import MailCore

/// The account's Google contacts and "other contacts" (people it wrote to), with the profile photos Google keeps for
/// them, as Gmail shows beside their mail.
extension GmailClient: ContactPhotoSyncing {
    public func contacts() async throws -> [Contact] {
        try await contactsWithPhotos().contacts
    }

    /// One entry per address. Google's lettered placeholders aren't photos: the app draws its own initials.
    public func contactsWithPhotos() async throws -> (contacts: [Contact], photos: [String: URL]) {
        let saved = try await people("people/me/connections", fields: "personFields", listedIn: \.connections)
        let others = try await people("otherContacts", fields: "readMask", listedIn: \.otherContacts)
        let everyone = saved + others
        var photos: [String: URL] = [:]
        for person in everyone {
            guard let photo = person.photo else { continue }
            // An address listed twice keeps the first photo, as it keeps the first name.
            for contact in person.contacts where photos[contact.address.lowercased()] == nil {
                photos[contact.address.lowercased()] = photo
            }
        }
        return (everyone.flatMap(\.contacts), photos)
    }

    /// Every page of one People API list.
    private func people(_ path: String, fields: String, listedIn list: KeyPath<GooglePeoplePage, [GooglePerson]?>)
        async throws -> [GooglePerson]
    {
        var people: [GooglePerson] = []
        var pageToken: String?
        repeat {
            var items = [
                URLQueryItem(name: fields, value: "names,emailAddresses,photos"),
                URLQueryItem(name: "pageSize", value: "1000"),
            ]
            if let pageToken { items.append(URLQueryItem(name: "pageToken", value: pageToken)) }
            let url = GmailConfiguration.peopleBaseURL.appending(path: path).appending(queryItems: items)
            let page: GooglePeoplePage = try await send(url, method: "GET", payload: nil)
            people += page[keyPath: list] ?? []
            pageToken = page.nextPageToken
        } while pageToken != nil
        return people
    }
}

/// One page of `people.connections.list` or `otherContacts.list`.
struct GooglePeoplePage: Decodable {
    let connections: [GooglePerson]?
    let otherContacts: [GooglePerson]?
    let nextPageToken: String?
}

struct GooglePerson: Decodable {
    struct Name: Decodable {
        let displayName: String?
    }

    struct Email: Decodable {
        let value: String?
    }

    struct Photo: Decodable {
        let url: URL?
        /// A placeholder Google drew from the person's initial, not a photo of them.
        let `default`: Bool?
    }

    /// Google's photo URLs end in the size they're served at, which defaults to 100 pixels; an avatar is drawn at up
    /// to 40 points on a 3x screen.
    static let photoSide = 160

    let names: [Name]?
    let emailAddresses: [Email]?
    let photos: [Photo]?

    /// One contact per address, all with the person's name.
    var contacts: [Contact] {
        let name = names?.first?.displayName
        return (emailAddresses ?? []).compactMap(\.value).filter { !$0.isEmpty }.map {
            Contact(name: name, address: $0)
        }
    }

    /// The person's photo, sized for an avatar; `nil` when Google has only a placeholder.
    var photo: URL? {
        guard let url = photos?.first(where: { $0.default != true })?.url, url.scheme == "https" else { return nil }
        return Self.sized(url)
    }

    /// `url` served at `photoSide` pixels when it names its size (`…=s100`), else as it is.
    static func sized(_ url: URL) -> URL {
        let text = url.absoluteString
        guard let size = text.firstMatch(of: /=s\d+$/) else { return url }
        return URL(string: text.replacingCharacters(in: size.range, with: "=s\(photoSide)")) ?? url
    }
}
