import Foundation

/// A service whose address book carries people's profile photos, read with the contacts in the same requests. Gmail's
/// does, through the People API. Graph keeps a photo per contact behind a request each, and IMAP has no address book,
/// so Outlook's and iCloud's providers don't conform.
public protocol ContactPhotoSyncing: MailProvider {
    /// The same contacts as `contacts()`, with the photo URL of each one that has a photo, by lowercased address.
    func contactsWithPhotos() async throws -> (contacts: [Contact], photos: [String: URL])
}
