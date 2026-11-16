public import Foundation
import MailCore
public import MailStore

/// Where a sender's picture comes from, best first: their photo in the reader's Contacts, the profile photo an
/// account's address book keeps for them (Google's), then their company's logo. Shared by the mail screens and
/// new-mail alerts, which keep what they fetch in the same App Group folder.
public struct SenderPictureSources: Sendable {
    private let profiles: ProfilePhotos
    private let logos: SenderLogos

    public init(directory: URL, database: MailDatabase) {
        profiles = ProfilePhotos(directory: directory.appending(path: "Profiles")) {
            try? database.photoURL(for: $0)
        }
        logos = SenderLogos(directory: directory)
    }

    /// The picture as image data, or `nil` when there is none, and the sender's initials should show.
    public func picture(for address: String) async -> Data? {
        if let photo = ContactPhotos.photo(for: address) { return photo }
        if let photo = await profiles.photo(for: address) { return photo }
        return await logos.logo(for: address)
    }
}
